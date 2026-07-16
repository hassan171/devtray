import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';


/// Renders an HTML string in a scrollable dialog — used to preview HTML
/// responses (server-rendered error pages, SSO redirects, …).
class HtmlPreviewDialog extends StatelessWidget {
  final String html;
  final DevtrayTheme theme;

  const HtmlPreviewDialog({super.key, required this.html, required this.theme});

  static Future<void> show(BuildContext context, String html) {
    final theme = DevtrayTheme.of(context);
    return showDialog<void>(
      context: context,
      builder: (_) => HtmlPreviewDialog(html: html, theme: theme),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DevtrayThemeScope(
      theme: theme,
      child: Dialog(
        backgroundColor: theme.background,
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Icon(Icons.html, size: 18, color: theme.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('HTML Preview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: theme.text)),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: Icon(Icons.close, size: 18, color: theme.text),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.border),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Html(data: html),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
