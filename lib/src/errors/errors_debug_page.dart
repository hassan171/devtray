import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import '../network/components/network_formatters.dart';
import '../network/network_log_store.dart';
import '../widgets/copyable_section.dart';
import '../widgets/debug_search_bar.dart';
import 'error_store.dart';

String errorSourceLabel(ErrorSource s) => switch (s) {
      ErrorSource.flutter => 'Flutter',
      ErrorSource.uncaught => 'Uncaught',
      ErrorSource.network => 'Network',
      ErrorSource.manual => 'Reported',
    };

/// The request side of a failed call, as a copyable block.
String _requestSummary(NetworkError e) {
  final entry = e.entry;
  return [
    '${entry.method} ${entry.uri}',
    'Status: ${entry.statusCode ?? 'no response'}',
    'Duration: ${formatDuration(entry.duration)}',
    if (entry.errorMessage != null) 'Error: ${entry.errorMessage}',
    '',
    'Request Headers:',
    prettyMap(entry.requestHeaders),
    if (entry.requestBody != null) ...['', 'Request Body:', prettyJson(entry.requestBody)],
  ].join('\n');
}

/// Uncaught exceptions and framework errors, captured on-device.
///
/// The point of this page is the errors nobody was watching the console for —
/// so opening it clears the launcher's unseen-error badge.
class ErrorsDebugPage extends DebugPage {
  const ErrorsDebugPage();

  @override
  String get title => 'Errors';

  @override
  IconData? get icon => Icons.error_outline;

  @override
  Widget build(BuildContext context) => const _ErrorsView();
}

class _ErrorsView extends StatefulWidget {
  const _ErrorsView();

  @override
  State<_ErrorsView> createState() => _ErrorsViewState();
}

class _ErrorsViewState extends State<_ErrorsView> {
  String _search = '';
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    // The user is looking at them now — drop the badge.
    ErrorStore.instance.markAllSeen();
  }

  List<ErrorEntry> _filtered(List<ErrorEntry> entries) {
    if (_search.isEmpty) return entries;
    final q = _search.toLowerCase();
    return entries.where((e) => e.error.toString().toLowerCase().contains(q) || (e.context?.toLowerCase().contains(q) ?? false)).toList();
  }

  String _asPlainText(ErrorEntry e) {
    if (e.error case final NetworkError n) {
      return [
        n.toString(),
        '',
        _requestSummary(n),
        '',
        'Response Headers:',
        prettyHeaders(n.entry.responseHeaders),
        '',
        'Response Body:',
        prettyJson(n.entry.responseBody),
      ].join('\n');
    }

    return [
      e.error.toString(),
      if (e.context != null) '\nContext: ${e.context}',
      if (e.library != null) 'Library: ${e.library}',
      if (e.stackTrace != null) '\n${e.stackTrace}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final store = ErrorStore.instance;

    return ValueListenableBuilder<int>(
      valueListenable: store.tick,
      builder: (context, _, _) {
        final entries = store.entries;
        final filtered = _filtered(entries);

        ErrorEntry? selected;
        for (final e in entries) {
          if (e.id == _selectedId) selected = e;
        }

        if (selected != null) {
          return _ErrorDetail(
            entry: selected,
            onBack: () => setState(() => _selectedId = null),
            asPlainText: _asPlainText,
          );
        }

        return Column(
          children: [
            DebugSearchBar(
              hintText: 'Search errors',
              total: filtered.length,
              onChanged: (v) => setState(() => _search = v),
              actions: [
                IconButton(
                  tooltip: 'Clear',
                  icon: Icon(Icons.delete_outline, color: t.error),
                  onPressed: () {
                    store.clear();
                    setState(() => _selectedId = null);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline, size: 32, color: t.success),
                          const SizedBox(height: 8),
                          Text(
                            entries.isEmpty ? 'No errors' : 'No matches',
                            style: TextStyle(color: t.textMuted),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final e = filtered[i];
                        return _ErrorRow(entry: e, onTap: () => setState(() => _selectedId = e.id));
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ErrorRow extends StatelessWidget {
  final ErrorEntry entry;
  final VoidCallback onTap;

  const _ErrorRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: t.error.withValues(alpha: 0.05),
          border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
        ),
        child: Row(
          children: [
            Icon(
              entry.source == ErrorSource.network ? Icons.cloud_off : Icons.error_outline,
              size: 16,
              color: t.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: t.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${errorSourceLabel(entry.source)}${entry.context == null ? '' : ' · ${entry.context}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: t.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: t.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ErrorDetail extends StatelessWidget {
  final ErrorEntry entry;
  final VoidCallback onBack;
  final String Function(ErrorEntry) asPlainText;

  const _ErrorDetail({required this.entry, required this.onBack, required this.asPlainText});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back, size: 18, color: t.text),
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                errorSourceLabel(entry.source),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.error),
              ),
            ),
            IconButton(
              tooltip: 'Copy report',
              icon: Icon(Icons.copy, size: 16, color: t.text),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: asPlainText(entry)));
                showDebugToast('Error report copied');
              },
            ),
          ],
        ),
        Divider(color: t.border),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CopyableSection(title: 'Exception', body: entry.error.toString(), titleColor: t.error),
                if (entry.context != null) CopyableSection(title: 'Context', body: entry.context!),
                if (entry.library != null) CopyableSection(title: 'Library', body: entry.library!),

                // A failed request has no useful Dart stack — the throw site is
                // deep inside the HTTP client. Show the request instead; that's
                // the actual diagnostic.
                if (entry.error case final NetworkError e) ...[
                  CopyableSection(title: 'Request', body: _requestSummary(e)),
                  CopyableSection(title: 'Response Headers', body: prettyHeaders(e.entry.responseHeaders)),
                  CopyableSection(title: 'Response Body', body: prettyJson(e.entry.responseBody)),
                ] else
                  CopyableSection(title: 'Stack Trace', body: entry.stackTrace?.toString() ?? 'No stack trace'),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
