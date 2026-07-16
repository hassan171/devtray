# devtray_dio

Feeds devtray's **Network** page from a `Dio` client.

Part of [devtray](https://github.com/hassan171/devtray) — the overlay, the pages and the stores live in the
core package; this is just the dio glue.

## Install

```yaml
dependencies:
  devtray: ^0.1.0
  devtray_dio: ^0.1.0
```

## Usage

```dart
import 'package:devtray_dio/devtray_dio.dart';

final dio = Dio()..interceptors.add(DebugDioInterceptor());
```

Every request through this `Dio` shows up on the Network page — method, status, timing, headers and bodies — and mock rules you add from the page intercept here.

## Docs

Full setup and the other integrations: **[https://github.com/hassan171/devtray](https://github.com/hassan171/devtray)**

## License

MIT — see [LICENSE](LICENSE).
