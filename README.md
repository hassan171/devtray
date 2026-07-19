# devtray

An in-app debugging overlay for Flutter: a draggable floating button that opens a tabbed
tools panel over your running app.

Eight built-in pages — **Timeline** (everything on one time axis, with UI-freeze detection),
**Network** (with mocking), **Logs** (errors folded in), **State**, **Storage**, **Visual**,
**Device** and **Export** — and every other tab is one you add.

You decide **whether** it exists, **when** it opens, and **how** it's presented.

## Quick start

Swap `runApp` for `runDebugApp` and list the pages you want:

```dart
import 'package:devtray/devtray.dart';

void main() => runDebugApp(
  app: const MyApp(),
  enabled: kDebugMode,
  pages: [NetworkDebugPage(), LogsDebugPage()],
);
```

Full setup, the page catalogue and the extension points: **[packages/devtray](packages/devtray)**.

## Packages

The core carries **no runtime dependencies** beyond Flutter. Each integration owns exactly
one, so an app that uses `http` and Riverpod never compiles dio or bloc.

| Package | What it adds |
|---|---|
| [`devtray`](packages/devtray) | The overlay, the pages, the stores. Start here. |
| [`devtray_dio`](packages/devtray_dio) | `DebugDioInterceptor` → the Network page |
| [`devtray_http`](packages/devtray_http) | `DebugHttpClient` → the Network page |
| [`devtray_bloc`](packages/devtray_bloc) | `DebugBlocObserver` → the State page |
| [`devtray_riverpod`](packages/devtray_riverpod) | `DebugRiverpodObserver` → the State page |
| [`devtray_prefs`](packages/devtray_prefs) | `shared_preferences` browsing + mock-rule persistence |
| [`devtray_hive`](packages/devtray_hive) | Browse and edit Hive boxes |
| [`devtray_sqflite`](packages/devtray_sqflite) | Every SQLite table, discovered from the schema |
| [`devtray_log_file`](packages/devtray_log_file) | Write logs to disk, and load a past run back |
| [`devtray_device`](packages/devtray_device) | Real device, OS and app facts |
| [`devtray_html`](packages/devtray_html) | Preview HTML response bodies |

The integrations are **additive, not alternatives**: install `_bloc` and `_riverpod`
together and both fill the same State page — useful precisely when you're migrating between
them. Same for `_dio` and `_http`.

The **pages** all live in the core; only the adapters move. `NetworkDebugPage` reads from a
transport-agnostic store, so dio and http feed the same page.

## Installing before it's on pub.dev

Not published yet — until it is, depend on it from git. The integration packages declare a
hosted `devtray: ^0.4.0` that can't resolve yet, so the core needs an override:

```yaml
dependencies:
  devtray:
    git:
      url: https://github.com/hassan171/devtray.git
      path: packages/devtray
  devtray_dio:
    git:
      url: https://github.com/hassan171/devtray.git
      path: packages/devtray_dio

# Delete this block once devtray is on pub.dev.
dependency_overrides:
  devtray:
    git:
      url: https://github.com/hassan171/devtray.git
      path: packages/devtray
```

The override is what makes the integrations resolve against the git core instead of the
hosted one that doesn't exist yet. Without it, pub fails with *"every version of
`devtray_dio` from git depends on `devtray` from hosted … version solving failed"*.

## Example

A multi-tab notes app wired to every integration:

```
cd example && flutter run
```

## Development

This repo is a [pub workspace](https://dart.dev/tools/pub/workspaces) — one shared lockfile
and one `pub get` for every package, no melos:

```
flutter pub get      # resolves all 11 members
flutter analyze      # analyzes all of them
```

Workspace members resolve to each other locally, so an edit to the core flows straight into
the integrations and the example with no publish round-trip.

## License

MIT — see [LICENSE](LICENSE).
