# devtray_riverpod

Feeds devtray's **State** page from Riverpod providers.

Part of [devtray](https://github.com/hassan171/devtray) — the overlay, the pages and the stores live in the
core package; this is just the flutter_riverpod glue.

## Install

```yaml
dependencies:
  devtray: ^0.1.0
  devtray_riverpod: ^0.1.0
```

## Usage

```dart
import 'package:devtray_riverpod/devtray_riverpod.dart';

ProviderScope(
  observers: [DebugRiverpodObserver()],
  child: const MyApp(),
)
```

Name your providers — `StateProvider(..., name: 'cart')` — for readable rows; otherwise the page falls back to the runtime type.

Already have an observer? Chain it: `DebugRiverpodObserver(next: MyObserver())`.

## Docs

Full setup and the other integrations: **[https://github.com/hassan171/devtray](https://github.com/hassan171/devtray)**

## License

MIT — see [LICENSE](LICENSE).
