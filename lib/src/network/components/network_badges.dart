import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';

/// Colored pill showing the HTTP verb.
class MethodBadge extends StatelessWidget {
  final String method;
  const MethodBadge({super.key, required this.method});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final color = switch (method.toUpperCase()) {
      'GET' => t.accent,
      'POST' => t.success,
      'PUT' || 'PATCH' => t.warning,
      'DELETE' => t.error,
      _ => t.textMuted,
    };

    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(
        method.toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Outlined pill showing the response status code, colored by class.
class StatusBadge extends StatelessWidget {
  final int? code;
  final bool failed;
  const StatusBadge({super.key, required this.code, required this.failed});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final c = code;

    final Color color;
    if (failed || (c != null && c >= 400)) {
      color = t.error;
    } else if (c != null && c >= 300) {
      color = t.warning;
    } else if (c != null && c >= 200) {
      color = t.success;
    } else {
      color = t.textMuted;
    }

    return Container(
      width: 36,
      padding: const EdgeInsets.symmetric(vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(4)),
      child: Text(
        c?.toString() ?? '-',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// `label: value` pair used in the detail header.
class InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const InfoChip({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: TextStyle(fontSize: 11, color: t.textMuted)),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.text)),
      ],
    );
  }
}
