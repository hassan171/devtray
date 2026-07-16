import 'package:flutter/widgets.dart';

/// Renders an HTML response body — usually in a dialog.
///
/// The core has **no HTML renderer**, on purpose. Rendering HTML means a real
/// parser (`flutter_html` and its own dependency tree), and it exists for one
/// button on one tab: previewing a server-rendered error page or an SSO redirect.
/// Bundling it would make every app pay for it, including the great majority
/// whose API only ever returns JSON.
///
/// So the core defines the *shape* of a previewer and calls it if given one:
///
/// ```dart
/// // with debug_overlay_html installed
/// NetworkDebugPage(onPreviewHtml: HtmlPreviewDialog.show)
/// ```
///
/// Without one, the Network page's preview button simply isn't drawn. The
/// feature is absent rather than broken — which is the honest outcome, since the
/// core genuinely can't render HTML.
typedef DebugHtmlPreviewer = void Function(BuildContext context, String html);
