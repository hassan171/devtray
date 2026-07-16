import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';
import '../../core/debug_text_styles.dart';
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
  //.${t.millisecond.toString().padLeft(3, '0')}
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// One line in the log stream. Tapping opens the full detail (`LogDetailDialog`)
/// — log lines are frequently long (a dumped JSON payload, a stack trace), and
/// truncating with no way to see the rest makes the page useless.
///
/// **Always exactly one line.** The tag sits inline with the message and the
/// message ellipsises rather than wrapping. Uniform line height is what makes a
/// stream scannable — variable-height rows destroy the rhythm your eye follows,
/// and everything cut off is one tap away.
///
/// **One row type, not two.** Errors and ordinary logs live in the same store
/// and the same stream, so they render through the same widget; an error only
/// differs in what its dialog shows. Two row widgets made one stream look like
/// two pages stapled together, and drifted apart every time either was touched.
///
/// Laid out as a console line rather than a card: no per-row border or gap, just
/// a level-coloured spine down the leading edge. A log list's job is to show a
/// lot of lines at once; chrome per row halves how many you get.
class LogRow extends StatelessWidget {
  final LogEntry entry;
  final VoidCallback onTap;

  const LogRow({super.key, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final color = logLevelColor(entry.level, t);
    final isError = entry.isError;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        child: Container(
          decoration: BoxDecoration(
            color: isError ? t.error.withValues(alpha: 0.05) : null,
            border: Border(bottom: BorderSide(color: t.border.withValues(alpha: 0.4), width: 0.5)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The spine carries the level, so severity is peripheral — you
                // find the red line without reading a single word.
                Container(width: 2, color: color.withValues(alpha: isError ? 0.9 : 0.5)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                    child: Row(
                      children: [
                        // Tabular figures: the timestamp column stays a column
                        // instead of jittering line to line.
                        Text(
                          formatLogTime(entry.time),
                          style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 11, height: 1.4),
                        ),
                        const SizedBox(width: 8),
                        // Tinted, not a solid block: at this size a filled badge
                        // outshouts the message, which is what you're reading.
                        Container(
                          width: 30,
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(logLevelLabel(entry.level), style: DebugTextStyles.label(color: color, fontSize: 9)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (entry.tag != null)
                                  TextSpan(
                                    text: '${entry.tag!} ',
                                    style: DebugTextStyles.debugMono(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                // An error's headline is its title (first line
                                // only); a log's is its message.
                                TextSpan(text: isError ? entry.title : entry.message),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DebugTextStyles.debugMono(color: t.text, fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
