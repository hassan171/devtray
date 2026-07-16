# devtray_http

Feeds devtray's **Network** page from a `package:http` client.

Part of [devtray](https://github.com/hassan171/devtray) — the overlay, the pages and the stores live in the
core package; this is just the http glue.

## Install

```yaml
dependencies:
  devtray: ^0.1.0
  devtray_http: ^0.1.0
```

## Usage

```dart
import 'package:devtray_http/devtray_http.dart';

final client = DebugHttpClient(http.Client());

final res = await client.get(Uri.parse('https://api.example.com/notes'));
```

Wrap any `http.Client`. Requests appear on the Network page alongside dio traffic — both adapters feed the same transport-agnostic store, so you can install both while migrating.

## Docs

Full setup and the other integrations: **[https://github.com/hassan171/devtray](https://github.com/hassan171/devtray)**

## License

MIT — see [LICENSE](LICENSE).
