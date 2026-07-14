import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hz_toast/hz_toast.dart';

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
            IconButton(
              tooltip: 'Copy',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(Icons.copy, size: 14, color: t.textMuted),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: body));
                showDebugToast('$title copied');
              },
            ),
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

/// Feedback toast. Context-free — HzToast renders through its own overlay, so
/// this is safe to call from any callback (including after an await).
///
/// Requires the host app to have HzToast installed (its builder/overlay wired
/// into MaterialApp), which is HzToast's normal setup.
void showDebugToast(String message, {bool isError = false}) {
  HzToast.show(HzToastData(message, type: isError ? HzToastType.error : HzToastType.success));
}
