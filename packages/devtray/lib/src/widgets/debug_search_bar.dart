import 'dart:async';

import 'package:flutter/material.dart';

import '../core/devtray_theme.dart';
import '../core/debug_text_styles.dart';

/// Search field + count + trailing actions. Shared by the Logs, Errors and
/// Network pages so they all filter the same way.
///
/// Drawn as one grouped surface — field, count and actions inside a single
/// frame — rather than a stock `TextField` flanked by loose `IconButton`s.
/// Drawing them as one object is what separates a tool from a form.
///
/// [onChanged] is **debounced** — see [debounce]. Filtering here means a linear
/// pass over a full ring buffer (1000 log lines, 500 requests), so firing it on
/// every keystroke was dropping frames while typing. The field itself stays
/// uncontrolled, so typing is still instant; only the filtering waits.
class DebugSearchBar extends StatefulWidget {
  final String hintText;
  final int total;
  final ValueChanged<String> onChanged;

  /// How long typing must pause before [onChanged] fires. [Duration.zero]
  /// disables debouncing — used by tests that assert on filtering synchronously.
  final Duration debounce;

  /// Trailing icon buttons (clear, copy-all, …).
  final List<Widget> actions;

  const DebugSearchBar({
    super.key,
    required this.total,
    required this.onChanged,
    this.hintText = 'Search',
    this.debounce = const Duration(milliseconds: 200),
    this.actions = const [],
  });

  @override
  State<DebugSearchBar> createState() => _DebugSearchBarState();
}

class _DebugSearchBarState extends State<DebugSearchBar> {
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounceTimer?.cancel();
    if (widget.debounce == Duration.zero) {
      widget.onChanged(value);
      return;
    }
    _debounceTimer = Timer(widget.debounce, () {
      if (mounted) widget.onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final hintText = widget.hintText;
    final total = widget.total;
    final actions = widget.actions;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(Icons.search, size: 16, color: t.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              // The query is matched against captured output — mono keeps it
              // honest with the lines it's filtering.
              style: DebugTextStyles.debugMono(color: t.text, fontSize: 13),
              cursorColor: t.accent,
              cursorWidth: 1.5,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(color: t.textMuted, fontSize: 13),
                isDense: true,
                // The container is the frame — the field shouldn't draw a second.
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: _onChanged,
            ),
          ),
          // A live readout of the filter, so it sits with the field rather than
          // floating among the actions.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$total',
              style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          if (actions.isNotEmpty) Container(width: 1, height: 20, color: t.border.withValues(alpha: 0.8)),
          ...actions,
          const SizedBox(width: 2),
        ],
      ),
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
    final t = DevtrayTheme.of(context);

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
    final t = DevtrayTheme.of(context);

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
