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
  }

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
  }

  void _backToLive() {
    setState(() {
      _session = null;
      _sessionEntries = null;
      _search = '';
      _conditions.clear();
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
  Map<String, FilterField<LogEntry>> _fields(List<String> tags) => {
    'Level': FilterField(name: 'Level', valueOf: (e) => logLevelLabel(e.level), suggestions: LogLevel.values.map(logLevelLabel).toList()),
    'Source': FilterField(name: 'Source', valueOf: _sourceOf, suggestions: ['log', 'flutter', 'uncaught', 'network', 'reported']),
    'Tag': FilterField(name: 'Tag', valueOf: (e) => e.tag ?? '', suggestions: tags),
    'Message': FilterField(name: 'Message', valueOf: (e) => e.message),
    'Time': FilterField(name: 'Time', valueOf: (e) => formatLogTime(e.time)),
  };

  List<LogEntry> _filtered(List<LogEntry> entries, Map<String, FilterField<LogEntry>> fields) {
    // `searchable` is already lowercased and cached, so this is a plain
    // substring test per entry — no per-keystroke string building.
    final q = _search.toLowerCase();
    final searched = q.isEmpty ? entries : entries.where((e) => e.searchable.contains(q)).toList();
    return applyFilter(searched, _conditions, fields);
  }

  String _asPlainText(List<LogEntry> entries) {
    // Oldest-first, so a pasted dump reads chronologically.
    return entries.reversed.map((e) => '${formatLogTime(e.time)} ${logLevelLabel(e.level)} ${e.tag == null ? '' : '[${e.tag}] '}${e.message}').join('\n');
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
    final fields = _fields(tags);
    final filtered = _filtered(entries, fields);

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
              : Container(
                  color: t.surface,
                  child: ListView.builder(
                    // Reads like a console: newest at the bottom, new lines
                    // pushing older ones up, and the view pinned to the latest
                    // rather than stranding you at the top of a stale list.
                    //
                    // `reverse` rather than reversing the data: the store is
                    // already newest-first, so index 0 is the newest — which
                    // `reverse: true` renders at the bottom. Flipping the list
                    // itself would mean re-sorting on every single rebuild.
                    reverse: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final e = filtered[i];
                      // Keyed by id — entries are inserted at index 0, so
                      // every row would otherwise re-associate with a
                      // different entry on each new line.
                      return LogRow(key: ValueKey(e.id), entry: e, onTap: () => LogDetailDialog.show(context, e));
                    },
                  ),
                ),
        ),
      ],
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
