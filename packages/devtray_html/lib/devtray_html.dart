/// HTML response preview for `devtray`'s Network page.
///
/// ```dart
/// NetworkDebugPage(onPreviewHtml: HtmlPreviewDialog.show)
/// ```
///
/// Renders an HTML response body — a server-rendered error page, an SSO
/// redirect — instead of leaving you to read its markup.
///
/// This is the one integration that's a **widget** rather than an adapter, and
/// the reason `NetworkDebugPage` takes a hook at all: rendering HTML means a
/// real parser (`flutter_html` and its own dependency tree), for one button on
/// one tab. Bundling it would make every app pay for it, including the great
/// majority whose API only ever returns JSON. Without the hook the core simply
/// doesn't draw the button — the feature is absent rather than broken.
library;

export 'src/html_preview_dialog.dart';
