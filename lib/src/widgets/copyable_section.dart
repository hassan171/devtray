import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/debug_overlay_theme.dart';

/// A titled, monospaced, selectable block of text with a copy button.
class CopyableSection extends StatelessWidget {
  final String title;
  final String body;
  final Color? titleColor;

  const CopyableSection({super.key, required this.title, required this.body, this.titleColor});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: titleColor ?? t.text),
              ),
            ),
            CopyButton(text: body, tooltip: 'Copy'),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(6)),
          child: SelectableText(
            body.isEmpty ? '-' : body,
            style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: t.text),
          ),
        ),
      ],
    );
  }
}

/// Copies [text] to the clipboard, flashing a checkmark instead of announcing
/// itself. No toast, no snackbar — nothing to dismiss, and nothing covering the
/// data you were reading.
///
/// Copies **verbatim** — headers, tokens and bodies exactly as captured. A
/// copied cURL command is meant to be replayable, which it wouldn't be with the
/// auth header scrubbed.
class CopyButton extends StatefulWidget {
  final String text;
  final String tooltip;
  final IconData icon;
  final double size;

  const CopyButton({super.key, required this.text, this.tooltip = 'Copy', this.icon = Icons.copy, this.size = 14});

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  static const _flashDuration = Duration(milliseconds: 1200);

  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;

    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(_flashDuration, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return IconButton(
      tooltip: _copied ? 'Copied' : widget.tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: widget.text.isEmpty ? null : _copy,
      icon: Icon(_copied ? Icons.check : widget.icon, size: widget.size, color: _copied ? t.success : t.textMuted),
    );
  }
}
