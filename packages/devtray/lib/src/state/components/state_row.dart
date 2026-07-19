import 'package:flutter/material.dart';

import '../../core/devtray_theme.dart';
import '../../core/debug_text_styles.dart';
import '../devtray_state.dart';

/// The colour a source is spoken in — shared by the row's spine and its badges
/// so the two can't drift apart.
///
/// Order matters: an errored source is an errored source even if it later
/// closed, so the error reading wins.
Color sourceColor(BuildContext context, TrackedSource source) {
  final t = DevtrayTheme.of(context);
  if (source.error != null) return t.error;
  if (source.isClosed) return t.textMuted;
  return t.accent;
}

/// One source in the list: type, live state, change count.
///
/// Scanning this list is a **triage** task — same as the Network page, so it's
/// built the same way and for the same reasons:
///
///  * a **spine** down the leading edge carries the source's condition, so a
///    broken cubit is a red edge you catch peripherally rather than a badge you
///    have to read;
///  * the **type** is the identity, so it gets the weight;
///  * the **live state** is why you opened the page, so it's mono and directly
///    under the name;
///  * the change count uses **tabular figures** and is labelled, so a column of
///    bare integers doesn't read as "some number".
class StateRow extends StatelessWidget {
  final TrackedSource source;
  final bool isSelected;
  final VoidCallback onTap;

  const StateRow({super.key, required this.source, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final spine = sourceColor(context, source);
    final hasError = source.error != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        // The list is the primary interaction — a row that doesn't answer the
        // finger reads as broken.
        highlightColor: t.accent.withValues(alpha: 0.06),
        splashColor: t.accent.withValues(alpha: 0.10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isSelected
                ? t.accent.withValues(alpha: 0.10)
                : hasError
                ? t.error.withValues(alpha: 0.05)
                : null,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The spine. Widens on selection, so the current row is anchored
                // by shape and not only by a faint background tint.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  width: 2,
                  color: isSelected ? t.accent : spine.withValues(alpha: hasError ? 0.9 : 0.55),
                ),
                Expanded(
                  child: Opacity(
                    // A closed source is kept — you often want to see what it did
                    // just before its screen was popped — but shown as past-tense.
                    // Only the content dims; the spine stays legible.
                    opacity: source.isClosed ? 0.6 : 1,
                    child: Padding(
                      // 44px min height via vertical padding + two text lines:
                      // this is a touch target, not a table cell.
                      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        source.type,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: DebugTextStyles.debugMono(
                                          color: t.text,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                    if (source.isClosed) ...[
                                      const SizedBox(width: 6),
                                      StateTag(label: 'closed', color: t.textMuted, icon: Icons.block_rounded),
                                    ],
                                    if (hasError) ...[
                                      const SizedBox(width: 6),
                                      StateTag(label: 'error', color: t.error, icon: Icons.priority_high_rounded),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  // The live state — the thing you opened this
                                  // page for. Through display() so a registered
                                  // formatter / pretty default applies; the row
                                  // keeps it to one line. Pass the source type so
                                  // a source-scoped formatter can match.
                                  DevtrayState.instance.display(source.state, sourceType: source.type),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 11, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ChangeCount(count: source.changes.length),
                        ],
                      ),
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

/// How many times this source has changed.
///
/// A bare integer on the right edge is unreadable — 0 and 12 look like the same
/// kind of nothing. The glyph says what the number counts, and tabular figures
/// keep the column from wobbling as it ticks.
class _ChangeCount extends StatelessWidget {
  final int count;
  const _ChangeCount({required this.count});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    // Nothing has happened yet — say so quietly rather than showing a '0' that
    // reads like a real measurement.
    final idle = count == 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.change_history_rounded, size: 10, color: t.textMuted.withValues(alpha: idle ? 0.5 : 1)),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: DebugTextStyles.debugMono(
            color: t.textMuted.withValues(alpha: idle ? 0.5 : 1),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Small status pill — `closed`, `error`.
///
/// Carries a glyph as well as a colour, so the state survives grayscale and
/// colour-blindness. Tinted fill rather than a bare outline, to match the
/// Network page's badges.
class StateTag extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const StateTag({super.key, required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8, color: color),
          const SizedBox(width: 2),
          Text(label, style: DebugTextStyles.label(color: color, fontSize: 8)),
        ],
      ),
    );
  }
}
