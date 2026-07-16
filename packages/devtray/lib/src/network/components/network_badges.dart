import 'package:flutter/material.dart';

import '../../core/devtray_theme.dart';
import '../../core/debug_text_styles.dart';

/// The color a method is spoken in, shared by the badge and the row's spine so
/// they can't drift apart.
Color methodColor(BuildContext context, String method) {
  final t = DevtrayTheme.of(context);
  return switch (method.toUpperCase()) {
    'GET' => t.accent,
    'POST' => t.success,
    'PUT' || 'PATCH' => t.warning,
    'DELETE' => t.error,
    _ => t.textMuted,
  };
}

/// The color a status code is spoken in — by class, with transport failures
/// treated as errors.
Color statusColor(BuildContext context, int? code, bool failed) {
  final t = DevtrayTheme.of(context);
  if (failed || (code != null && code >= 400)) return t.error;
  if (code != null && code >= 300) return t.warning;
  if (code != null && code >= 200) return t.success;
  return t.textMuted;
}

/// Pill showing the HTTP verb.
///
/// Tinted surface + matching text rather than a solid block: at 10px a solid
/// fill makes the verb the loudest thing in the row, when the *path* is what
/// you're scanning for. The method is a qualifier, so it recedes — and the
/// method's color still carries on the row's spine.
///
/// Sized to its content, not a fixed width — `GET` and `DELETE` are different
/// words and padding them to a common box just adds dead space to every row.
class MethodBadge extends StatelessWidget {
  final String method;
  const MethodBadge({super.key, required this.method});

  @override
  Widget build(BuildContext context) {
    final color = methodColor(context, method);

    return Container(
      height: 18,
      width: 42,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(4)),
      alignment: Alignment.center,
      child: Text(method.toUpperCase(), style: DebugTextStyles.label(color: color, fontSize: 10)),
    );
  }
}

/// The response status code, colored by class.
///
/// Carries a leading glyph as well as the color, so the outcome survives
/// grayscale and colour-blindness — the code alone is the fallback, but a
/// scannable list shouldn't depend on reading three digits.
class StatusBadge extends StatelessWidget {
  final int? code;
  final bool failed;
  const StatusBadge({super.key, required this.code, required this.failed});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(context, code, failed);
    final c = code;

    // Not colour alone: a glyph says the same thing in grayscale.
    final IconData? glyph;
    if (failed) {
      glyph = Icons.close_rounded;
    } else if (c == null) {
      glyph = null;
    } else if (c >= 400) {
      glyph = Icons.priority_high_rounded;
    } else if (c >= 300) {
      glyph = Icons.subdirectory_arrow_right_rounded;
    } else if (c >= 200) {
      glyph = Icons.check_rounded;
    } else {
      glyph = null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (glyph != null) ...[Icon(glyph, size: 11, color: color), const SizedBox(width: 2)],
        Text(
          // A transport failure has no code — say so rather than showing '-',
          // which reads like a status we failed to parse.
          c?.toString() ?? (failed ? 'ERR' : '···'),
          style: DebugTextStyles.debugMono(color: color, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// `label: value` pair used in the detail header. The value is data, so it's
/// mono; the label is prose, so it isn't.
class InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const InfoChip({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: t.textMuted, letterSpacing: 0.3)),
        const SizedBox(width: 4),
        Text(
          value,
          style: DebugTextStyles.debugMono(color: t.text, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
