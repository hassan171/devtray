import 'dart:async';

import 'package:flutter/material.dart';

import '../core/devtray_theme.dart';
import '../core/debug_page.dart';
import '../core/debug_text_styles.dart';
import '../filter/debug_filter.dart';
import '../filter/debug_filter_builder.dart';
import '../widgets/copyable_section.dart';
import '../widgets/debug_search_bar.dart';
import 'components/log_detail_dialog.dart';
import 'components/log_row.dart';
import 'components/log_session_picker.dart';
import 'log_sink.dart';
import 'log_store.dart';

/// Captured logs **and** errors in one stream — `debugPrint`, `print` (under
/// [runDebugApp]), [LogStore.log], plus every framework/uncaught
/// error and forwarded network failure ([LogStore.report]).
///
/// One store, one entry type: errors are [LogEntry]s with [LogEntry.isError]
/// set, so `Source = network` (or `Level = ERR`) in the advanced filter isolates
/// an errors-only view. Search the text or build a JQL-style filter over level /
/// source / tag / message / time. Tap any row for its full detail — for an
/// error, the whole report (request, response, stack).
///
/// Rendered as a console: one line per entry, newest at the bottom.
class LogsDebugPage extends DebugPage {
  /// Past runs this page can load and browse.
  ///
  /// Null (the default) hides the session picker entirely — an app with no log
  /// persistence configured shouldn't be offered a browser for files that don't
  /// exist. Supply one and a folder button appears beside the search field.
  ///
  /// ```dart
  /// LogsDebugPage(sessionSource: DevtrayFileSessions(await LogSessionLoader.open()))
  /// ```
  ///
  /// See [LogSessionSource] — file-backed in `devtray_log_file`, but anything
  /// that can list and parse sessions fits.
  final LogSessionSource? sessionSource;

  const LogsDebugPage({this.sessionSource});

  @override
  String get title => 'Logs';

  @override
  IconData? get icon => Icons.article_outlined;

  @override
  Widget build(BuildContext context) => _LogsView(sessionSource: sessionSource);
}

/// The source a row carries in the Source filter: an error line reports its
/// origin tag (network/flutter/…); an ordinary log line is "log".
String _sourceOf(LogEntry e) => e.isError ? (e.tag ?? 'error') : 'log';

class _LogsView extends StatefulWidget {
  final LogSessionSource? sessionSource;

  const _LogsView({this.sessionSource});

  @override
  State<_LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<_LogsView> {
  String _search = '';

  /// Advanced conditions, AND-ed on top of the search. Kept in state so they
  /// survive rebuilds while the page is open.
  final List<FilterCondition<LogEntry>> _conditions = [];

  /// Drives the follow behaviour below. Owned by the State so it survives the
  /// rebuilds that arriving entries cause.
  final ScrollController _scroll = ScrollController();

  /// Whether the list is pinned to the newest entry.
  ///
  /// True while you're at the bottom, false the moment you scroll up to read
  /// something. This is the whole feature: a console that keeps scrolling while
  /// you're trying to read it is unusable, and one that *stops* following after
  /// you've scrolled back to the bottom is just as bad.
  ///
  /// A notifier rather than plain state so the jump-to-latest button can
  /// appear and disappear without rebuilding the list behind it.
  final ValueNotifier<bool> _following = ValueNotifier<bool>(true);

  /// Entries that arrived while you were scrolled up — the count on the
  /// jump-to-latest button, so "3 new" tells you whether it's worth looking.
  final ValueNotifier<int> _missed = ValueNotifier<int>(0);

  /// Newest entry id seen while following, for counting what came after.
  int? _lastSeenId;

  /// How close to the bottom still counts as "following".
  ///
  /// Not zero: a few pixels of overscroll, or a row part-way off the edge,
  /// shouldn't silently turn following off — and turning it off wrongly is the
  /// failure people notice, because the list stops updating for no visible
  /// reason.
  static const double _followThreshold = 40;

  /// The past run being viewed, or null for the live stream.
  ///
  /// A loaded session is held **separately** from [LogStore] rather than merged
  /// into it. Merging would make "what is happening now" indistinguishable from
  /// "what happened in a run that already ended" — and would mean a loaded
  /// session got re-exported by the sinks as though it were new.
  LogSessionInfo? _session;
  List<LogEntry>? _sessionEntries;
  bool _loadingSession = false;

  bool get _isViewingSession => _session != null;

  @override
  void initState() {
    super.initState();
    // The errors are on screen now — drop the launcher's error badge.
    LogStore.instance.markErrorsSeen();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _following.dispose();
    _missed.dispose();
    super.dispose();
  }

  /// Turns following on or off as you scroll.
  ///
  /// The list is `reverse: true`, so offset 0 is the bottom — the newest entry
  /// — and scrolling up into history increases the offset.
  void _onScroll() {
    if (!_scroll.hasClients) return;

    // A jump-to-latest in flight is an explicit intent to follow again, and it
    // must not be second-guessed by the scroll events its own animation
    // generates — see [_jumpToLatest].
    if (_jumping) return;

    final atBottom = _scroll.offset <= _followThreshold;
    if (atBottom == _following.value) return;

    _following.value = atBottom;
    if (atBottom) {
      // Caught up — nothing was missed.
      _missed.value = 0;
      _lastSeenId = null;
      _correctedForCount = 0;
    } else {
      // Mark the high-water line the moment following stops, so "new" means
      // "arrived since you looked away". Latching it during build instead would
      // tie it to whenever the next rebuild happened to run.
      _lastSeenId = _newestVisibleId;
      _missed.value = 0;
    }
  }

  /// Id of the newest entry that survived the current filter, captured on each
  /// build so [_onScroll] can mark the high-water line without re-filtering.
  int? _newestVisibleId;

  /// Entry id → row index, so the list can re-find an already-laid-out child
  /// after insertions shift every index. See the list's
  /// `findChildIndexCallback`.
  final Map<int, int> _indexOfId = {};

  /// How many arrivals the scroll offset has already been corrected for, so
  /// each new row is compensated once and only once.
  int _correctedForCount = 0;

  /// Counts entries that arrived while scrolled up.
  ///
  /// Called from the list build, which is the only place that knows what's
  /// actually in view after filtering — the store's own count would include
  /// entries the current filter excludes, and offering to jump to lines that
  /// aren't there would be worse than no count at all.
  void _trackMissed(List<LogEntry> filtered) {
    // Newest first, so index 0 is the latest. Recorded even while following, so
    // [_onScroll] has a high-water line to latch the instant you scroll away.
    _newestVisibleId = filtered.isEmpty ? null : filtered.first.id;

    // Following needs no maintenance: with `reverse: true` the newest entry
    // sits at offset 0, so staying at 0 keeps it in view for free. No
    // post-frame jump, and therefore nothing that can fire mid-drag and yank
    // the reader back.
    if (_following.value || filtered.isEmpty) return;

    final since = _lastSeenId;
    if (since == null) return;

    var count = 0;
    for (final e in filtered) {
      if (e.id <= since) break;
      count++;
    }

    // Deferred: this runs during build, and firing a notifier inline would mark
    // a listening widget dirty mid-frame.
    if (count != _missed.value) {
      scheduleMicrotask(() {
        if (mounted) _missed.value = count;
      });
    }

    // Hold the reader's place against insertion.
    //
    // The store inserts at index 0, which under `reverse: true` is the scroll
    // anchor — so every arrival adds a row *between* the origin and a
    // scrolled-up reader, sliding them one row further from it.
    // findChildIndexCallback keeps element identity across that shift but does
    // not move the viewport, so the offset has to be corrected by the extent of
    // what arrived.
    if (count > _correctedForCount && _scroll.hasClients) {
      final newRows = count - _correctedForCount;

      // Measured in ROWS, not in pixels of growth.
      //
      // Comparing maxScrollExtent across the frame is the obvious approach and
      // silently does nothing once the buffer is at its cap: one entry in, one
      // evicted out, extent unchanged. The content doesn't grow there, it
      // *slides*, and only a row count sees that. Rows are a uniform height
      // (LogRow is deliberately always one line), so rows × height is exact.
      final rowExtent = _rowExtent;
      if (rowExtent == null) return;

      // Never fight an in-progress scroll — correcting mid-drag reads as the
      // list refusing to stay where you put it.
      final position = _scroll.position;
      if (position.isScrollingNotifier.value) return;

      final target = (position.pixels + newRows * rowExtent).clamp(0.0, position.maxScrollExtent);

      // Consumed only once the correction is actually going to happen. Marking
      // these rows as handled before the guards above would mean a correction
      // skipped mid-drag is never made up, and the reader drifts by however
      // many rows arrived while they were moving.
      _correctedForCount = count;
      if (target == position.pixels) return;

      // Corrected DURING this build, not after it.
      //
      // A post-frame jumpTo is the obvious approach and is what caused a visible
      // flicker: the frame paints at the stale offset, then snaps. This runs in
      // build — before layout and paint — so the offset can be fixed up front
      // and the frame is simply drawn in the right place.
      //
      // correctPixels rather than jumpTo because that is what it is for:
      // adjusting the offset to account for a content change, without notifying
      // listeners or starting a scroll activity. Both would be wrong here —
      // nothing about the user's position has conceptually changed. Same
      // mechanism Flutter's own scroll anchoring uses.
      position.correctPixels(target);
    }
  }

  /// Height of a single row, derived from the list itself.
  ///
  /// Measured rather than hardcoded so a change to [LogRow]'s padding or text
  /// style can't silently break the correction above. Null until the list has
  /// laid out enough to divide by.
  double? get _rowExtent {
    if (!_scroll.hasClients) return null;
    final rows = _indexOfId.length;
    if (rows < 2) return null;

    final position = _scroll.position;
    if (!position.hasContentDimensions) return null;

    // maxScrollExtent covers everything except one viewport's worth.
    final total = position.maxScrollExtent + position.viewportDimension;
    final extent = total / rows;
    return extent > 0 ? extent : null;

  }

  /// Scrolls back to the newest entry and resumes following.
  ///
  /// Deliberately does **not** set `_following` itself. [_onScroll] owns that
  /// flag, and setting it here too meant the listener's "did it change?" guard
  /// saw no change during the animation and never reconciled — leaving the
  /// button on screen after it had done its job. One writer, no disagreement.
  void _jumpToLatest() {
    if (!_scroll.hasClients) return;

    _missed.value = 0;
    _lastSeenId = null;
    _correctedForCount = 0;

    // Following resumes NOW, on the intent, rather than being inferred from
    // where the scroll ends up.
    //
    // Inferring it was the bug behind "the button needs a second press":
    // entries arriving during the animation kept extending the end, so when the
    // listener looked, the offset genuinely wasn't at the bottom yet and the
    // flag stayed off. [_jumping] holds that decision for the duration, so the
    // animation's own scroll events can't undo it.
    _following.value = true;
    _jumping = true;

    // The newest entry is at offset 0. Animated rather than jumped: the point
    // is to show you where you landed, and a teleport to the bottom of a busy
    // console is disorienting.
    //
    // Target 0 rather than a measured extent, so entries arriving during the
    // animation cannot move the destination out from under it.
    _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut).whenComplete(() {
      // Released only after the animation, so the listener's first read is of
      // the final position rather than a mid-flight one.
      _jumping = false;
    });
  }

  /// True while [_jumpToLatest] is animating back to the newest entry.
  ///
  /// Suppresses [_onScroll]'s follow inference for the duration — see both.
  bool _jumping = false;

  Future<void> _openSession(LogSessionInfo session) async {
    setState(() {
      _session = session;
      _loadingSession = true;
      // Filters from the live view rarely mean anything against a different
      // run, and leaving them on looks like an empty session.
      _search = '';
      _conditions.clear();
    });

    final entries = await widget.sessionSource!.load(session);
    if (!mounted) return;

    setState(() {
      _sessionEntries = entries;
      _loadingSession = false;
    });
    _resetScroll();
  }

  void _backToLive() {
    setState(() {
      _session = null;
      _sessionEntries = null;
      _search = '';
      _conditions.clear();
    });
    // Different list, so the old offset means nothing — and returning to live
    // should land on the newest entry, following again.
    _resetScroll();
  }

  /// Back to the bottom, following, with nothing outstanding.
  void _resetScroll() {
    _following.value = true;
    _missed.value = 0;
    _lastSeenId = null;
    _correctedForCount = 0;

    // Deferred a frame: this is called from a view switch, and the list being
    // scrolled hasn't been laid out yet — jumping now would either assert or
    // act on the outgoing list's extents.
    //
    // Jumped, not animated: there is no continuity across a view change to
    // preserve, so an animation would just read as a glitch.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _showSessionPicker() async {
    final source = widget.sessionSource;
    if (source == null) return;

    final picked = await LogSessionPicker.show(context, source);
    if (picked == null || !mounted) return;

    await _openSession(picked);
  }

  /// The structured fields the advanced builder can target. Built fresh so tag
  /// suggestions reflect what's actually present.
  Map<String, FilterField<LogEntry>> _fields(List<String> tags, List<String> fieldKeys) => {
    'Level': FilterField(name: 'Level', valueOf: (e) => logLevelLabel(e.level), suggestions: LogLevel.values.map(logLevelLabel).toList()),
    'Source': FilterField(name: 'Source', valueOf: _sourceOf, suggestions: ['log', 'flutter', 'uncaught', 'network', 'reported']),
    'Tag': FilterField(name: 'Tag', valueOf: (e) => e.tag ?? '', suggestions: tags),
    'Message': FilterField(name: 'Message', valueOf: (e) => e.message),
    'Time': FilterField(name: 'Time', valueOf: (e) => formatLogTime(e.time)),
    // Matched as `key=value` text rather than per-key, because the fields
    // present vary line by line — a fixed column per key would be mostly empty.
    // `Fields contains userId=42` is the query people actually write.
    'Fields': FilterField(name: 'Fields', valueOf: (e) => e.fieldsLabel, suggestions: fieldKeys),
  };

  /// Field-key suggestions for the filter builder.
  ///
  /// Sampled from the newest entries rather than scanned across the whole
  /// buffer: this runs on every build, and walking 1000 entries per frame to
  /// populate an autocomplete would cost more than the suggestions are worth.
  /// The keys in play are almost always visible in the last few lines anyway,
  /// since ambient context and enrichers attach to everything.
  List<String> _fieldKeys(List<LogEntry> entries) {
    final keys = <String>{};
    for (final e in entries.take(30)) {
      keys.addAll(e.fields.keys);
    }
    return keys.toList()..sort();
  }

  List<LogEntry> _filtered(List<LogEntry> entries, Map<String, FilterField<LogEntry>> fields) {
    // `searchable` is already lowercased and cached, so this is a plain
    // substring test per entry — no per-keystroke string building.
    final q = _search.toLowerCase();
    final searched = q.isEmpty ? entries : entries.where((e) => e.searchable.contains(q)).toList();
    return applyFilter(searched, _conditions, fields);
  }

  String _asPlainText(List<LogEntry> entries) {
    // Oldest-first, so a pasted dump reads chronologically.
    return entries.reversed
        .map(
          (e) => '${formatLogTime(e.time)} ${logLevelLabel(e.level)} '
              '${e.tag == null ? '' : '[${e.tag}] '}${e.message}'
              // Trailing, so the message still starts at a predictable column.
              '${e.fields.isEmpty ? '' : '  {${e.fieldsLabel}}'}',
        )
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    // A loaded session is a fixed list — subscribing to the live store while
    // showing one would rebuild the page for entries it isn't displaying.
    if (_isViewingSession) return _buildSession(context);

    final store = LogStore.instance;
    return ValueListenableBuilder<int>(
      valueListenable: store.tick,
      builder: (context, _, _) => _buildBody(
        context,
        entries: store.entries,
        tags: store.tags.toList()..sort(),
      ),
    );
  }

  /// The past-session view: the same rows and search over a fixed list, plus a
  /// banner making it unmistakable that this is not live.
  Widget _buildSession(BuildContext context) {
    final t = DevtrayTheme.of(context);

    if (_loadingSession) {
      return Center(
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: t.textMuted)),
      );
    }

    final entries = _sessionEntries ?? const <LogEntry>[];
    final tags = <String>{for (final e in entries) if (e.tag != null) e.tag!}.toList()..sort();

    return Column(
      children: [
        _SessionBanner(session: _session!, count: entries.length, onBack: _backToLive),
        const SizedBox(height: 8),
        Expanded(child: _buildBody(context, entries: entries, tags: tags)),
      ],
    );
  }

  /// Shared by both modes — the search bar, the filter builder and the list.
  ///
  /// One body rather than two so a past session is searched and filtered
  /// exactly like the live stream, and neither can drift from the other.
  Widget _buildBody(BuildContext context, {required List<LogEntry> entries, required List<String> tags}) {
    final t = DevtrayTheme.of(context);
    final store = LogStore.instance;
    final fields = _fields(tags, _fieldKeys(entries));
    final filtered = _filtered(entries, fields);

    // Counted here because this is the only place that knows what survived the
    // filter. A saved session is fixed, so nothing can arrive to be missed.
    if (!_isViewingSession) _trackMissed(filtered);

    // entry id → index, for findChildIndexCallback. Rebuilt per build because
    // that is exactly when indices change; one pass over a list already being
    // walked to render.
    _indexOfId
      ..clear()
      ..addEntries([for (var i = 0; i < filtered.length; i++) MapEntry(filtered[i].id, i)]);


    return Column(
      children: [
        DebugSearchBar(
          hintText: _isViewingSession ? 'Search this session' : 'Search logs & errors',
          total: filtered.length,
          onChanged: (v) => setState(() => _search = v),
          actions: [
            // Copies the *filtered* view, so a narrowed-down stream is what
            // lands in the bug report.
            CopyButton(
              tooltip: 'Copy all',
              icon: Icons.copy_all,
              size: 16,
              isEmpty: filtered.isEmpty,
              text: () => _asPlainText(filtered),
            ),
            // Only offered when there are sessions to browse.
            if (widget.sessionSource != null && !_isViewingSession)
              IconButton(
                tooltip: 'Load a saved session',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(Icons.folder_open, size: 16, color: t.textMuted),
                onPressed: _showSessionPicker,
              ),
            // Clearing a past run from here would mean deleting a file from
            // behind a button labelled "clear logs" — the picker owns deletion.
            if (!_isViewingSession)
              IconButton(
                tooltip: 'Clear all logs',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(Icons.delete_outline, size: 16, color: t.error),
                onPressed: store.clear,
              ),
          ],
        ),
        const SizedBox(height: 8),
            DebugFilterBuilder<LogEntry>(
          conditions: _conditions,
          fields: fields,
          onAdd: () => setState(() => _conditions.add(FilterCondition())),
          onRemove: (i) => setState(() => _conditions.removeAt(i)),
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? _LogsEmptyState(
                  searching: entries.isNotEmpty || _conditions.isNotEmpty,
                  // A loaded session that parsed to nothing is a different
                  // problem from capture never having been installed.
                  isSession: _isViewingSession,
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: t.surface,
                        child: ListView.builder(
                          controller: _scroll,
                          // Reads like a console: newest at the bottom, new lines
                          // pushing older ones up, and the view pinned to the
                          // latest rather than stranding you at the top of a stale
                          // list.
                          //
                          // `reverse: true` is load-bearing for performance, not
                          // just presentation. It puts the newest entry at offset
                          // 0, so reaching it costs nothing and only the visible
                          // rows are ever laid out. Rendering oldest-first instead
                          // puts the newest at maxScrollExtent, which means laying
                          // out the entire buffer just to find the end: 2.2s to
                          // open with 1000 entries, versus ~0.5s. Open is
                          // O(viewport), not O(buffer).
                          //
                          // The cost is that offset 0 is also where the store
                          // inserts, so arriving entries land between the origin
                          // and a scrolled-up reader. Two mechanisms cover that:
                          // `findChildIndexCallback` keeps element identity across
                          // the index shift, and _trackMissed corrects the offset
                          // by the extent of what arrived. Both are needed —
                          // identity alone does not move the viewport.
                          reverse: true,
                          // Rows are a fixed height, so the viewport can compute
                          // scroll geometry arithmetically instead of laying rows
                          // out to discover it.
                          itemExtent: LogRow.extent,
                          itemCount: filtered.length,
                          findChildIndexCallback: (Key key) => _indexOfId[(key as ValueKey<int>).value],
                          itemBuilder: (context, i) {
                            // Newest-first, matching `reverse: true` — index 0 is
                            // the newest and renders at the bottom.
                            final e = filtered[i];
                            // The key is what findChildIndexCallback resolves, so
                            // it must be the stable entry id.
                            return LogRow(key: ValueKey(e.id), entry: e, onTap: () => LogDetailDialog.show(context, e));
                          },
                        ),
                      ),
                    ),

                    // Offered only when you've scrolled away from the newest
                    // entry — while following there is nothing to jump to.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 8,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _following,
                        builder: (context, following, _) => following
                            ? const SizedBox.shrink()
                            : Center(
                                child: ValueListenableBuilder<int>(
                                  valueListenable: _missed,
                                  builder: (context, missed, _) => _JumpToLatestButton(missed: missed, onTap: _jumpToLatest),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Returns to the newest entry, and says how much arrived while you were away.
///
/// Floats over the list rather than taking a row in the toolbar: it only exists
/// while you're scrolled up, and a control that appears and disappears in the
/// header would shift the list under you — the exact problem this feature is
/// about.
class _JumpToLatestButton extends StatelessWidget {
  final int missed;
  final VoidCallback onTap;

  const _JumpToLatestButton({required this.missed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: t.accent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_downward, size: 12, color: t.background),
              const SizedBox(width: 5),
              Text(
                // The count matters: "47 new" and "1 new" are different
                // decisions about whether to look now.
                missed > 0 ? '$missed new' : 'Jump to latest',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.background),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marks the view as a past run rather than the live stream.
///
/// Deliberately loud. The failure this prevents is reading a stale session as
/// though it were what the app is doing right now — which looks exactly like a
/// bug that has stopped reproducing.
class _SessionBanner extends StatelessWidget {
  final LogSessionInfo session;
  final int count;
  final VoidCallback onBack;

  const _SessionBanner({required this.session, required this.count, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 14, color: t.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saved session — not live',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.warning),
                ),
                Text(
                  '${session.label} · $count ${count == 1 ? 'entry' : 'entries'}',
                  style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onBack,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: t.accent,
            ),
            icon: const Icon(Icons.bolt, size: 14),
            label: const Text('Live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Shown when the stream has nothing to show.
///
/// An empty console says nothing about whether it's working or broken. When
/// nothing has been captured at all, the usual cause is that the capture hooks
/// were never installed — so say that, rather than leaving "No logs yet" in a
/// void.
class _LogsEmptyState extends StatelessWidget {
  /// True when entries exist but the search/filter excluded them all — a very
  /// different situation from having captured nothing.
  final bool searching;

  /// True in the loaded-session view, where "install capture" is the wrong
  /// advice — the file simply had nothing in it.
  final bool isSession;

  const _LogsEmptyState({required this.searching, this.isSession = false});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(searching ? Icons.search_off : Icons.article_outlined, size: 28, color: t.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              switch ((searching, isSession)) {
                (true, _) => 'No matching lines',
                (false, true) => 'This session is empty',
                (false, false) => 'No logs captured',
              },
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text),
            ),
            const SizedBox(height: 4),
            Text(
              switch ((searching, isSession)) {
                (true, _) => 'Nothing matches this search or filter.',
                // The file existed and parsed — it just had nothing in it.
                // Telling someone to install capture here would be wrong advice.
                (false, true) => 'The file was read, but held no readable entries.',
                (false, false) => 'debugPrint, print and uncaught errors land here once\n'
                    'capture is installed — start the app with runDebugApp(),\n'
                    'or bridge your own logger into LogStore.',
              },
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
