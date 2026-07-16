# devtray_bloc

Feeds devtray's **State** page from bloc and cubit.

Part of [devtray](https://github.com/hassan171/devtray) — the overlay, the pages and the stores live in the
core package; this is just the bloc glue.

## Install

```yaml
dependencies:
  devtray: ^0.1.0
  devtray_bloc: ^0.1.0
```

## Usage

```dart
import 'package:devtray_bloc/devtray_bloc.dart';

Bloc.observer = DebugBlocObserver();
```

Every bloc and cubit transition lands on the State page with its change history. Install alongside `devtray_riverpod` and both fill the same page.

## Docs

Full setup and the other integrations: **[https://github.com/hassan171/devtray](https://github.com/hassan171/devtray)**

## License

MIT — see [LICENSE](LICENSE).
