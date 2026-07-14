import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';
import '../log_store.dart';

Color logLevelColor(LogLevel level, DebugOverlayTheme t) => switch (level) {
      LogLevel.debug => t.textMuted,
      LogLevel.info => t.accent,
      LogLevel.warning => t.warning,
      LogLevel.error => t.error,
    };

String logLevelLabel(LogLevel level) => switch (level) {
      LogLevel.debug => 'DBG',
      LogLevel.info => 'INF',
      LogLevel.warning => 'WRN',
      LogLevel.error => 'ERR',
    };

String formatLogTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
}

/// One line in the log list. Tapping expands it — log lines are frequently
/// long (a dumped JSON payload), and truncating with no way to see the rest
/// makes the page useless.
class LogRow extends StatelessWidget {
  final LogEntry entry;
  final bool isExpanded;
  final VoidCallback onTap;

  const LogRow({super.key, required this.entry, required this.isExpanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final color = logLevelColor(entry.level, t);

    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: entry.level == LogLevel.error ? t.error.withValues(alpha: 0.06) : null,
          border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
        ),
        child: Row(
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
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              child: Text(
                logLevelLabel(entry.level),
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.tag != null)
                    Text(
                      entry.tag!,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                    ),
                  isExpanded
                      ? SelectableText(
                          entry.message,
                          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: t.text),
                        )
                      : Text(
                          entry.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: t.text),
                        ),
                  if (isExpanded && entry.error != null) ...[
                    const SizedBox(height: 4),
                    SelectableText(
                      '${entry.error}',
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: t.error),
                    ),
                  ],
                  if (isExpanded && entry.stackTrace != null) ...[
                    const SizedBox(height: 4),
                    SelectableText(
                      '${entry.stackTrace}',
                      style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: t.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
