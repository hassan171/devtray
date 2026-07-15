import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';
import '../state_inspector.dart';

/// One source in the list: type, current state, change count.
class StateRow extends StatelessWidget {
  final TrackedSource source;
  final bool isSelected;
  final VoidCallback onTap;

  const StateRow({super.key, required this.source, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return InkWell(
      onTap: onTap,
      child: Opacity(
        // A closed source is kept — you often want to see what it did just
        // before its screen was popped — but shown as past-tense.
        opacity: source.isClosed ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? t.accent.withValues(alpha: 0.12)
                : source.error != null
                    ? t.error.withValues(alpha: 0.06)
                    : null,
            border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            source.type,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.text),
                          ),
                        ),
                        if (source.isClosed) ...[
                          const SizedBox(width: 6),
                          _Tag(label: 'closed', color: t.textMuted, theme: t),
                        ],
                        if (source.error != null) ...[
                          const SizedBox(width: 6),
                          _Tag(label: 'error', color: t.error, theme: t),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // The live state — the thing you opened this page for.
                      // Through display() so a registered formatter / pretty
                      // default applies; the row keeps it to one line.
                      StateInspector.instance.display(source.state),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: t.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${source.changes.length}',
                style: TextStyle(fontSize: 11, color: t.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  final DebugOverlayTheme theme;

  const _Tag({required this.label, required this.color, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
