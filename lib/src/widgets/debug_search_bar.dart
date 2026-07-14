import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';

/// Search field + count + trailing actions. Shared by the Logs, Errors and
/// Network pages so they all filter the same way.
class DebugSearchBar extends StatelessWidget {
  final String hintText;
  final int total;
  final ValueChanged<String> onChanged;

  /// Trailing icon buttons (clear, copy-all, …).
  final List<Widget> actions;

  const DebugSearchBar({
    super.key,
    required this.total,
    required this.onChanged,
    this.hintText = 'Search',
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Row(
      children: [
        Expanded(
          child: TextField(
            style: TextStyle(color: t.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: t.textMuted, fontSize: 13),
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18, color: t.textMuted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: t.accent)),
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        Text('$total', style: TextStyle(color: t.textMuted, fontSize: 12)),
        ...actions,
      ],
    );
  }
}

/// A row of toggleable filter chips — log levels, error sources, tags.
class DebugFilterChips<T> extends StatelessWidget {
  final List<T> options;
  final Set<T> selected;
  final String Function(T) labelOf;
  final Color Function(T)? colorOf;
  final ValueChanged<T> onToggle;

  const DebugFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onToggle,
    this.colorOf,
  });

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final option in options)
          _Chip(
            label: labelOf(option),
            // An empty selection means "no filter" — show everything as active,
            // rather than an all-dimmed row that looks like nothing matches.
            isSelected: selected.isEmpty || selected.contains(option),
            color: colorOf?.call(option) ?? t.accent,
            onTap: () => onToggle(option),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.isSelected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(color: isSelected ? color : t.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? color : t.textMuted,
          ),
        ),
      ),
    );
  }
}
