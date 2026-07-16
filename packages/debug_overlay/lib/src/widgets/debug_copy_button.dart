import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/debug_overlay_theme.dart';

/// Copies [text], and says so by **becoming** "Copied" for a moment.
///
/// Not a toast: a snackbar would cover the very data you just copied, and it
/// reports success somewhere other than where you looked. The confirmation
/// belongs on the control you pressed.
///
/// Shared by the Device and Export pages — one button, so the two can't drift
/// into confirming differently.
class DebugCopyButton extends StatefulWidget {
  /// Built lazily, on press. Serialising the whole page on every rebuild just to
  /// have a string ready for a button that may never be pressed is waste.
  final String Function() text;

  final String label;

  /// Compact icon-only form, for a crowded header.
  final bool iconOnly;

  const DebugCopyButton({
    super.key,
    required this.text,
    this.label = 'Copy all',
    this.iconOnly = false,
  });

  @override
  State<DebugCopyButton> createState() => _DebugCopyButtonState();
}

class _DebugCopyButtonState extends State<DebugCopyButton> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _copy() {
    // Confirm first, write second — deliberately NOT `await`ed.
    //
    // `Clipboard.setData` is a platform channel call. If the platform is slow,
    // or has no handler at all (a widget test, an unsupported desktop
    // embedder), the await never returns and the button sits there looking
    // broken — pressed, but never acknowledging it. That's the worst outcome:
    // the user re-taps, or assumes the copy failed when it didn't.
    //
    // The confirmation is UI state, so it's driven by the press, which is the
    // thing we actually know happened.
    Clipboard.setData(ClipboardData(text: widget.text()));

    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final color = _copied ? t.success : t.accent;
    final icon = _copied ? Icons.check_rounded : Icons.copy_rounded;

    if (widget.iconOnly) {
      return IconButton(
        tooltip: _copied ? 'Copied' : widget.label,
        onPressed: _copy,
        icon: Icon(icon, size: 16, color: color),
      );
    }

    return TextButton.icon(
      onPressed: _copy,
      style: TextButton.styleFrom(
        // A real tap target, and a tinted ground so the button reads as a
        // control rather than a stray blue word.
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        backgroundColor: color.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: Icon(icon, size: 14, color: color),
      // Fixed width for the label: 'Copy all' and 'Copied' are different
      // lengths, and a button that resizes as you press it makes the header
      // twitch. Left-aligned so the text doesn't slide under the icon either.
      label: SizedBox(
        width: 54,
        child: Text(
          _copied ? 'Copied' : widget.label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
