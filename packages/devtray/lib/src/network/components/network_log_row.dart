import 'package:flutter/material.dart';

import '../../core/devtray_theme.dart';
import '../../core/debug_text_styles.dart';
import '../mocking/mock_interceptor.dart';
import '../network_log_store.dart';
import 'network_badges.dart';
import 'network_formatters.dart';

/// Marks a row whose response never came from the server.
class _MockedBadge extends StatelessWidget {
  const _MockedBadge();

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.16),
        border: Border.all(color: t.warning.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text('MOCKED', style: DebugTextStyles.label(color: t.warning, fontSize: 8)),
    );
  }
}

/// One row in the request list: method, path/host, status, duration.
///
/// Scanning a request list is a **triage** task — you're looking for the one
/// that failed, or the one that was slow. So the row is built around making
/// outcome and identity readable without reading:
///
///  * a **spine** down the leading edge carries the status colour, so a failure
///    is a red edge you catch peripherally rather than a number you parse;
///  * the **path** is the identity, so it gets the weight, in mono;
///  * the **host** recedes — it's usually identical on every row, so it's noise
///    until you need it;
///  * numbers use **tabular figures**, so the right edge stays a column instead
///    of wobbling as durations tick.
class NetworkLogRow extends StatelessWidget {
  final NetworkLogEntry entry;
  final bool isSelected;
  final VoidCallback onTap;

  const NetworkLogRow({super.key, required this.entry, required this.isSelected, required this.onTap});

  /// Height of one row, and the list's `itemExtent`.
  ///
  /// Every row is the same shape — two single-line texts in fixed padding — so
  /// this is a fact about the layout rather than a guess. Declaring it lets the
  /// list compute its scroll geometry arithmetically instead of laying rows out
  /// to discover it, which is what keeps a 500-entry buffer from stalling the
  /// frame.
  ///
  /// Must stay in step with the `height:` in [build].
  static const double extent = 50;

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final failed = entry.status == NetworkLogStatus.failed;
    final pending = entry.status == NetworkLogStatus.pending;

    // The spine says "what happened": the status colour once it's known, the
    // method's colour while in flight (there's no outcome yet to report).
    final spine = pending ? methodColor(context, entry.method) : statusColor(context, entry.statusCode, failed);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        // A visible press layer — the list is the primary interaction, and a
        // row that doesn't answer the finger reads as broken.
        highlightColor: t.accent.withValues(alpha: 0.06),
        splashColor: t.accent.withValues(alpha: 0.10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isSelected
                ? t.accent.withValues(alpha: 0.10)
                : failed
                ? t.error.withValues(alpha: 0.05)
                : null,
          ),
          // A fixed height rather than IntrinsicHeight.
          //
          // Every row is the same two single-line texts inside fixed padding, so
          // the intrinsic pass was measuring a height that never varies — and
          // paying for a second layout walk of the whole subtree on every row,
          // every frame. It is also what lets the list set `itemExtent`, which
          // is worth far more: with it the viewport can compute scroll geometry
          // arithmetically instead of laying out rows to find out where things
          // are.
          //
          // If the row ever gains a variable-height element, this constant and
          // NetworkLogRow.extent must change together.
          height: NetworkLogRow.extent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The spine. Widens when selected, so the current row is anchored
              // by shape and not only by a faint background tint.
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: 2,
                color: isSelected ? t.accent : spine.withValues(alpha: failed || isSelected ? 0.9 : 0.55),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Row(
                    children: [
                      MethodBadge(method: entry.method),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              entry.uri.path.isEmpty ? entry.uri.toString() : entry.uri.path,
                              style: DebugTextStyles.debugMono(color: t.text, fontSize: 12, fontWeight: FontWeight.w500, height: 1.3),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 1),
                            Row(
                              children: [
                                // Never let a faked response pass for a real one.
                                if (entry.extras.containsKey(kMockedExtraLabel)) ...[const _MockedBadge(), const SizedBox(width: 4)],
                                Flexible(
                                  child: Text(
                                    entry.uri.host,
                                    style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 11, height: 1.3),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Status and timing read as one column on the right edge.
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (pending)
                            SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: t.textMuted))
                          else
                            StatusBadge(code: entry.statusCode, failed: failed),
                          const SizedBox(height: 1),
                          Text(formatDuration(entry.duration), style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 11, height: 1.3)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
