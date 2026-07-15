import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';

/// Search field + result count + clear-all button.
class NetworkSearchBar extends StatelessWidget {
  final int total;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const NetworkSearchBar({super.key, required this.total, required this.onChanged, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Row(
      children: [
        Expanded(
          child: TextField(
            style: TextStyle(color: t.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search URL, method, status',
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
        IconButton(
          tooltip: 'Clear',
          onPressed: onClear,
          icon: Icon(Icons.delete_outline, color: t.error),
        ),
      ],
    );
  }
}
