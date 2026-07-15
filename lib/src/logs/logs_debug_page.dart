import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import '../errors/error_detail_view.dart';
import '../errors/error_store.dart';
import '../filter/debug_filter.dart';
import '../filter/debug_filter_builder.dart';
import '../widgets/copyable_section.dart';
import '../widgets/debug_search_bar.dart';
import 'components/log_row.dart';
import 'log_store.dart';

/// Captured logs **and** errors in one stream — `debugPrint`, `print` (under
/// [DebugOverlayCapture.runApp]), [LogStore.log], plus every framework/uncaught
/// error and forwarded network failure (which [ErrorStore] mirrors in as
/// error-level lines).
///
/// One store, one entry type: errors arrive here as [LogEntry]s carrying an
/// [LogEntry.errorRef], so `Source = network` (or `Level = ERR`) in the
/// advanced filter reproduces the old standalone Errors view without a separate
/// tab. Search the text, one-tap the quick chips, or build a JQL-style filter
/// over level / source / tag / message / time. Expand an error row to see its
/// full report (request, response, stack) inline.
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
  final Set<LogLevel> _levels = {};
  final Set<String> _tags = {};
  int? _expandedId;

  /// Advanced conditions, AND-ed on top of the search + chips. Kept in state so
  /// they survive rebuilds while the page is open.
  final List<FilterCondition<LogEntry>> _conditions = [];

  @override
  void initState() {
    super.initState();
    // The errors are on screen now (folded into this list) — drop the badge.
    ErrorStore.instance.markAllSeen();
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
    final quick = entries.where((e) {
      // An empty chip set means "everything" — see DebugFilterChips.
      if (_levels.isNotEmpty && !_levels.contains(e.level)) return false;
      if (_tags.isNotEmpty && (e.tag == null || !_tags.contains(e.tag))) return false;
      if (q.isNotEmpty && !e.searchable.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    return applyFilter(quick, _conditions, fields);
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
                CopyButton(tooltip: 'Copy all', icon: Icons.copy_all, size: 18, text: _asPlainText(filtered)),
                IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.delete_outline, color: t.error),
                  onPressed: () {
                    // Clears the forwarded error lines too; also reset the badge
                    // source so it doesn't re-badge from stale entries.
                    store.clear();
                    ErrorStore.instance.clear();
                    setState(() => _expandedId = null);
                  },
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
                  ? Center(
                      child: Text(entries.isEmpty ? 'No logs yet' : 'No matches', style: TextStyle(color: t.textMuted)),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final e = filtered[i];
                        final expanded = e.id == _expandedId;
                        void onTap() => setState(() => _expandedId = expanded ? null : e.id);

                        // An error row expands into the full report; a plain log
                        // line uses the existing inline expansion.
                        if (e.errorRef case final ErrorEntry err) {
                          return _ErrorLogRow(entry: e, error: err, isExpanded: expanded, onTap: onTap);
                        }
                        return LogRow(entry: e, isExpanded: expanded, onTap: onTap);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// An error-level log row that expands into the same rich report the standalone
/// Errors page shows.
class _ErrorLogRow extends StatelessWidget {
  final LogEntry entry;
  final ErrorEntry error;
  final bool isExpanded;
  final VoidCallback onTap;

  const _ErrorLogRow({required this.entry, required this.error, required this.isExpanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: t.error.withValues(alpha: 0.06),
          border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatLogTime(entry.time),
                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: t.textMuted),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: t.error, borderRadius: BorderRadius.circular(3)),
                  child: const Text(
                    'ERR',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(error.source == ErrorSource.network ? Icons.cloud_off : Icons.error_outline, size: 14, color: t.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        error.title,
                        maxLines: isExpanded ? null : 2,
                        overflow: isExpanded ? null : TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: t.text),
                      ),
                      Text(
                        '${errorSourceLabel(error.source)}${error.context == null ? '' : ' · ${error.context}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: t.textMuted),
                      ),
                    ],
                  ),
                ),
                Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 16, color: t.textMuted),
              ],
            ),
            if (isExpanded) ...[const SizedBox(height: 8), ErrorDetailSections(entry: error)],
          ],
        ),
      ),
    );
  }
}
