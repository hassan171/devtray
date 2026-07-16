# devtray_prefs

A **Storage** page adapter for `shared_preferences`, plus persistence for mock rules.

Part of [devtray](https://github.com/hassan171/devtray) — the overlay, the pages and the stores live in the
core package; this is just the shared_preferences glue.

## Install

```yaml
dependencies:
  devtray: ^0.1.0
  devtray_prefs: ^0.1.0
```

## Usage

```dart
import 'package:devtray_prefs/devtray_prefs.dart';

// Browse and edit prefs from the Storage page
StorageDebugPage(adapters: [SharedPreferencesStorageAdapter()])

// Make Network-page mock rules survive a restart
MockStore.instance.storage = SharedPreferencesMockRuleStorage();
```

Two independent pieces — use either. Without the second, mock rules are session-only and vanish on hot restart.

## Docs

Full setup and the other integrations: **[https://github.com/hassan171/devtray](https://github.com/hassan171/devtray)**

## License

MIT — see [LICENSE](LICENSE).
