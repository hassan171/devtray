import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import '../filter/debug_filter.dart';
import '../filter/debug_filter_builder.dart';
import '../widgets/copyable_section.dart';
import '../widgets/debug_search_bar.dart';
import 'components/log_detail_dialog.dart';
import 'components/log_row.dart';
import 'log_store.dart';

/// Captured logs **and** errors in one stream — `debugPrint`, `print` (under
/// [DebugOverlayCapture.runApp]), [LogStore.log], plus every framework/uncaught
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
  const LogsDebugPage();

  @override
  String get title => 'Logs';

  @override
  IconData? get icon => Icons.article_outlined;

  @override
  Widget build(BuildContext context) => const _LogsView();
}

/// The source a row carries in the Source filter: an error line reports its
/// origin tag (network/flutter/…); an ordinary log line is "log".
String _sourceOf(LogEntry e) => e.isError ? (e.tag ?? 'error') : 'log';

class _LogsView extends StatefulWidget {
  const _LogsView();

  @override
  State<_LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<_LogsView> {
  String _search = '';

  /// Advanced conditions, AND-ed on top of the search. Kept in state so they
  /// survive rebuilds while the page is open.
  final List<FilterCondition<LogEntry>> _conditions = [];

  @override
  void initState() {
    super.initState();
    // The errors are on screen now — drop the launcher's error badge.
    LogStore.instance.markErrorsSeen();
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
    final q = _search.toLowerCase();
    final searched = q.isEmpty ? entries : entries.where((e) => e.searchable.toLowerCase().contains(q)).toList();
    return applyFilter(searched, _conditions, fields);
  }

  String _asPlainText(List<LogEntry> entries) {
    // Oldest-first, so a pasted dump reads chronologically.
    return entries.reversed.map((e) => '${formatLogTime(e.time)} ${logLevelLabel(e.level)} ${e.tag == null ? '' : '[${e.tag}] '}${e.message}').join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final store = LogStore.instance;

    return ValueListenableBuilder<int>(
      valueListenable: store.tick,
      builder: (context, _, _) {
        final entries = store.entries;
        final tags = store.tags.toList()..sort();
        final fields = _fields(tags);
        final filtered = _filtered(entries, fields);

        return Column(
          children: [
            DebugSearchBar(
              hintText: 'Search logs & errors',
              total: filtered.length,
              onChanged: (v) => setState(() => _search = v),
              actions: [
                // Copies the *filtered* view, so a narrowed-down stream is what
                // lands in the bug report.
                CopyButton(tooltip: 'Copy all', icon: Icons.copy_all, size: 16, text: _asPlainText(filtered)),
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
                  ? _LogsEmptyState(searching: entries.isNotEmpty || _conditions.isNotEmpty)
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
                          return LogRow(entry: e, onTap: () => LogDetailDialog.show(context, e));
                        },
                      ),
                    ),
            ),
          ],
        );
      },
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

  const _LogsEmptyState({required this.searching});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(searching ? Icons.search_off : Icons.article_outlined, size: 28, color: t.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              searching ? 'No matching lines' : 'No logs captured',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text),
            ),
            const SizedBox(height: 4),
            Text(
              searching
                  ? 'Nothing matches this search or filter.'
                  : 'debugPrint, print and uncaught errors land here once\n'
                        'capture is installed — start the app with runDebugApp(),\n'
                        'or bridge your own logger into LogStore.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
