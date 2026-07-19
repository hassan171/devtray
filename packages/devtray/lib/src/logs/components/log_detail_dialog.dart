import 'package:flutter/material.dart';

import '../../core/devtray_theme.dart';
import '../../core/debug_text_styles.dart';
import '../../widgets/copyable_section.dart';
import '../error_log_detail.dart';
import '../log_store.dart';
import 'log_row.dart';

/// One log line in full: its message, and — for an error — the whole report
/// (exception, context, and either the failed request/response or the stack).
///
/// A dialog rather than an inline expansion. Expanding in place fought the
/// stream in two ways: the row grew, shoving every line above it (the list is
/// bottom-anchored, so the thing you tapped moves), and a long stack trace
/// pushed the rest of the console off-screen entirely. A dialog leaves the
/// stream exactly where it was and gives the report room to be read.
class LogDetailDialog extends StatelessWidget {
  final LogEntry entry;

  const LogDetailDialog({super.key, required this.entry});

  static Future<void> show(BuildContext context, LogEntry entry) {
    return showDialog<void>(
      context: context,
      builder: (_) => DevtrayThemeScope(
        // The dialog is pushed on the app's Navigator, outside the overlay's
        // subtree — so it can't inherit the theme and has to carry it across.
        theme: DevtrayTheme.of(context),
        child: LogDetailDialog(entry: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final color = logLevelColor(entry.level, t);
    final isError = entry.isError;

    return Dialog(
      backgroundColor: t.background,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: t.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: the same level badge and timestamp the row carried, so the
            // dialog is visibly the line you tapped.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(4)),
                    child: Text(logLevelLabel(entry.level), style: DebugTextStyles.label(color: color, fontSize: 9)),
                  ),
                  const SizedBox(width: 8),
                  Text(formatLogTime(entry.time), style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 11)),
                  // Expanded, not Flexible+Spacer: a Spacer takes all the free
                  // space for itself, which squeezed these to an ellipsis while
                  // half the header sat empty.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(
                        children: [
                          if (entry.tag != null)
                            Flexible(
                              child: Text(
                                entry.tag!,
                                overflow: TextOverflow.ellipsis,
                                style: DebugTextStyles.debugMono(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                          if (isError && entry.source != null) ...[
                            if (entry.tag != null) const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                errorSourceLabel(entry.source!),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: t.textMuted),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // The whole line as text — the reason you opened this.
                  CopyButton(tooltip: 'Copy report', size: 16, text: () => isError ? errorAsPlainText(entry) : entry.message),
                  IconButton(
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: Icon(Icons.close, size: 16, color: t.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: t.border, height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isError)
                      // The full report: exception, context, and the request or
                      // the stack.
                      ErrorDetailSections(entry: entry)
                    else ...[
                      CopyableSection(title: 'Message', body: entry.message),
                      // A plain log line can still carry an error object and a
                      // stack — a bridged logger's `error:`/`stackTrace:`.
                      if (entry.error != null) CopyableSection(title: 'Error', body: '${entry.error}', titleColor: t.error),
                      if (entry.stackTrace != null) CopyableSection(title: 'Stack Trace', body: '${entry.stackTrace}'),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
