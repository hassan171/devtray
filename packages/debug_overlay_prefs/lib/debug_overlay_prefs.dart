/// `shared_preferences` support for `debug_overlay`. Two unrelated things that
/// happen to need the same package:
///
/// **Browse and edit your prefs** — a Storage page adapter:
///
/// ```dart
/// StorageDebugPage(adapters: [const SharedPreferencesStorageAdapter()])
/// ```
///
/// **Keep mock rules across a hot restart** — otherwise you re-add "force
/// /orders to 500" every time, which is exactly when you're iterating on an
/// error state:
///
/// ```dart
/// MockStore.instance.storage = SharedPreferencesMockRuleStorage();
/// runDebugApp(app: MyApp(), persistMockRules: true);
/// ```
///
/// Both are opt-in for the same reason: the core can't depend on
/// `shared_preferences`, or every app would carry it for a debug tool. Only the
/// rules are stored — no logs, no request bodies, so none of the PII concerns
/// that make persisting the *data* a bad idea.
library;

export 'src/shared_preferences_mock_storage.dart';
export 'src/shared_preferences_storage_adapter.dart';
