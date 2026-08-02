# devtray_html

Renders HTML response bodies on devtray's **Network** page.

Part of [devtray](https://github.com/hassan171/devtray) — the overlay, the pages and the stores live in the
core package; this is just the flutter_html glue.

## Install

```yaml
dependencies:
  devtray: ^0.6.2
  devtray_html: ^0.6.2
```

## Usage

```dart
import 'package:devtray_html/devtray_html.dart';

NetworkDebugPage(onPreviewHtml: HtmlPreviewDialog.show)
```

Without a previewer the Network page hides its HTML button, since the core can't render markup. `onPreviewHtml` is a plain `void Function(BuildContext, String)` — pass your own renderer instead if you prefer.

## Docs

Full setup and the other integrations: **[https://github.com/hassan171/devtray](https://github.com/hassan171/devtray)**

## License

MIT — see [LICENSE](LICENSE).
