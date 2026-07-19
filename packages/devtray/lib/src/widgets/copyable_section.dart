import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/devtray_theme.dart';
import '../core/debug_text_styles.dart';

/// A titled, monospaced, selectable block of text with a copy button.
class CopyableSection extends StatelessWidget {
  final String title;
  final String body;
  final Color? titleColor;

  const CopyableSection({super.key, required this.title, required this.body, this.titleColor});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final isEmpty = body.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              // Uppercased by the *style*, not by rewriting the string:
              // `toUpperCase()` would change the widget's actual text, which
              // breaks anything searching for the title and makes screen readers
              // spell it out letter by letter.
              child: Text(
                title,
                style: DebugTextStyles.label(color: titleColor ?? t.textMuted, fontSize: 10),
              ),
            ),
            CopyButton(text: () => body, isEmpty: isEmpty, tooltip: 'Copy'),
          ],
        ),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: t.border.withValues(alpha: 0.6)),
          ),
          child: SelectableText(
            isEmpty ? 'empty' : body,
            // This is the densest data in the tool — a payload dump. It was
            // asking for the bare `monospace` alias, which only resolves on
            // Android/Linux and silently fell back to a *proportional* font
            // everywhere else, wrecking the indentation of pretty-printed JSON.
            // The bundled family renders the same on every platform.
            style: DebugTextStyles.debugMono(
              color: isEmpty ? t.textMuted : t.text,
              fontSize: 12,
              // Payloads are read line by line — a little leading makes nested
              // JSON scannable instead of a wall.
              height: 1.45,
            ),
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
  /// Built lazily, on press.
  ///
  /// Callers hand over whole-page serialisations here — every filtered log line
  /// joined, a full cURL command with its JSON-encoded body. Materialising that
  /// on every rebuild, for a button that may never be pressed, was costing more
  /// than the page it sits on. Same reasoning as [DebugCopyButton.text].
  final String Function() text;

  /// Whether there is anything to copy — the button disables when true.
  ///
  /// Separate from [text] so the disabled state stays free: answering "is there
  /// anything here" must not require building the string we were trying to
  /// avoid building.
  final bool isEmpty;

  final String tooltip;
  final IconData icon;
  final double size;

  const CopyButton({
    super.key,
    required this.text,
    this.isEmpty = false,
    this.tooltip = 'Copy',
    this.icon = Icons.copy,
    this.size = 14,
  });

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

  void _copy() {
    // Not awaited, deliberately — see the note in DebugCopyButton._copy. A
    // platform channel with no handler (widget test, unsupported embedder)
    // never returns, and the button would sit there looking broken.
    Clipboard.setData(ClipboardData(text: widget.text()));

    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(_flashDuration, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return IconButton(
      tooltip: _copied ? 'Copied' : widget.tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: widget.isEmpty ? null : _copy,
      icon: Icon(_copied ? Icons.check : widget.icon, size: widget.size, color: _copied ? t.success : t.textMuted),
    );
  }
}
