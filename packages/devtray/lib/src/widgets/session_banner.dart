import 'package:flutter/material.dart';

import '../core/debug_text_styles.dart';
import '../core/devtray_theme.dart';

/// Marks a view as showing a saved run rather than live capture.
///
/// Shared by the Logs and Network pages: both can open a past session, and the
/// one thing that must never be ambiguous is which of the two you are looking
/// at. One banner rather than two that drift.
class SessionBanner extends StatelessWidget {
  /// The run's name — a timestamp reads best.
  final String label;

  /// How many things the session holds.
  final int count;

  /// What one of them is called, singular and plural.
  final String noun;
  final String pluralNoun;

  final VoidCallback onBack;

  const SessionBanner({
    super.key,
    required this.label,
    required this.count,
    required this.noun,
    required this.pluralNoun,
    required this.onBack,
  });

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
                  '$label · $count ${count == 1 ? noun : pluralNoun}',
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
