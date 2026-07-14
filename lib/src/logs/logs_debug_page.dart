import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import '../widgets/copyable_section.dart';
import '../widgets/debug_search_bar.dart';
import 'components/log_row.dart';
import 'log_store.dart';

/// Captured log output — `debugPrint`, `print` (when running under
/// [DebugOverlayCapture.runApp]), and anything sent to [LogStore.log].
///
/// Filter by level and tag, search the text, expand a line to select it, and
/// copy the whole filtered view out as plain text for a bug report.
class LogsDebugPage extends DebugPage {
  const LogsDebugPage();

  @override
  String get title => 'Logs';

  @override
  IconData? get icon => Icons.article_outlined;

  @override
  Widget build(BuildContext context) => const _LogsView();
}

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

  List<LogEntry> _filtered(List<LogEntry> entries) {
    final q = _search.toLowerCase();
    return entries.where((e) {
      // An empty filter set means "everything" — see DebugFilterChips.
      if (_levels.isNotEmpty && !_levels.contains(e.level)) return false;
      if (_tags.isNotEmpty && (e.tag == null || !_tags.contains(e.tag))) return false;
      if (q.isNotEmpty && !e.searchable.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  String _asPlainText(List<LogEntry> entries) {
    // Oldest-first, so a pasted dump reads chronologically.
    return entries.reversed
        .map((e) => '${formatLogTime(e.time)} ${logLevelLabel(e.level)} ${e.tag == null ? '' : '[${e.tag}] '}${e.message}')
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final store = LogStore.instance;

    return ValueListenableBuilder<int>(
      valueListenable: store.tick,
      builder: (context, _, _) {
        final entries = store.entries;
        final filtered = _filtered(entries);
        final tags = store.tags.toList()..sort();

        return Column(
          children: [
            DebugSearchBar(
              hintText: 'Search logs',
              total: filtered.length,
              onChanged: (v) => setState(() => _search = v),
              actions: [
                IconButton(
                  tooltip: 'Copy all',
                  icon: Icon(Icons.copy_all, size: 18, color: t.text),
                  onPressed: filtered.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: _asPlainText(filtered)));
                          showDebugToast('${filtered.length} log lines copied');
                        },
                ),
                IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.delete_outline, color: t.error),
                  onPressed: () {
                    store.clear();
                    setState(() => _expandedId = null);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                DebugFilterChips<LogLevel>(
                  options: LogLevel.values,
                  selected: _levels,
                  labelOf: logLevelLabel,
                  colorOf: (l) => logLevelColor(l, t),
                  onToggle: (l) => setState(() => _levels.contains(l) ? _levels.remove(l) : _levels.add(l)),
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: DebugFilterChips<String>(
                      options: tags,
                      selected: _tags,
                      labelOf: (tag) => tag,
                      onToggle: (tag) => setState(() => _tags.contains(tag) ? _tags.remove(tag) : _tags.add(tag)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        entries.isEmpty ? 'No logs yet' : 'No matches',
                        style: TextStyle(color: t.textMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final e = filtered[i];
                        return LogRow(
                          entry: e,
                          isExpanded: e.id == _expandedId,
                          onTap: () => setState(() => _expandedId = _expandedId == e.id ? null : e.id),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
