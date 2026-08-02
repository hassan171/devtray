# devtray

An in-app debugging overlay for Flutter: a draggable floating button that opens a tabbed
tools panel over your running app.

Eight built-in pages — **Timeline** (everything on one time axis, with UI-freeze detection),
**Network** (with mocking), **Logs** (errors folded in), **State**, **Storage**, **Visual**,
**Device** and **Export** — and every other tab is one you add.

You decide **whether** it exists, **when** it opens, and **how** it's presented.

<p align="center">
  <img src="https://raw.githubusercontent.com/hassan171/devtray/main/docs/assets/hero.gif"
       alt="Dragging the devtray button open and switching between the Timeline, Network and Logs pages"
       width="320">
</p>

## Quick start

Swap `runApp` for `runDebugApp` and list the pages you want:

```dart
import 'package:devtray/devtray.dart';

void main() => runDebugApp(
  () => const MyApp(),
  pages: [NetworkDebugPage(), LogsDebugPage()],
);
```

Full setup, the page catalogue and the extension points: **[packages/devtray](packages/devtray)**.

## The pages

**Network** — every request, with the detail pane on the right. Mocking turns it from an
observer into a test harness: force a 500, inject latency, simulate offline.

<img src="https://raw.githubusercontent.com/hassan171/devtray/main/docs/assets/network.png" alt="The Network page: a list of requests with status and duration, and a detail pane showing request headers and body" width="100%">

**Logs** — `debugPrint`, your own logger and uncaught errors on one list. Tapping an error
opens the exception, its stack trace, and the [context](packages/devtray#context-on-every-entry)
attached at the time.

<img src="https://raw.githubusercontent.com/hassan171/devtray/main/docs/assets/logs.png" alt="The Logs page with an error detail dialog showing the exception, context fields and stack trace" width="100%">

**Timeline** — requests, logs, state changes and jank on one time axis, so you can see what
the app was doing when it stalled.

<img src="https://raw.githubusercontent.com/hassan171/devtray/main/docs/assets/timeline.png" alt="The Timeline page: network, log, state and jank lanes on a shared time axis" width="100%">

<table>
<tr>
<td width="50%"><img src="https://raw.githubusercontent.com/hassan171/devtray/main/docs/assets/storage.png" alt="The Storage page, editing a value" width="100%"></td>
<td width="50%"><img src="https://raw.githubusercontent.com/hassan171/devtray/main/docs/assets/state.png" alt="The State page showing a bloc transition history" width="100%"></td>
</tr>
<tr>
<td><b>Storage</b> — browse <i>and edit</i>, types preserved</td>
<td><b>State</b> — bloc and Riverpod fill the same page</td>
</tr>
<tr>
<td><img src="https://raw.githubusercontent.com/hassan171/devtray/main/docs/assets/visual.png" alt="The Visual page with debug painting flags" width="100%"></td>
<td><img src="https://raw.githubusercontent.com/hassan171/devtray/main/docs/assets/export.png" alt="The Export page previewing a bug report" width="100%"></td>
</tr>
<tr>
<td><b>Visual</b> — layout bounds, repaint rainbow</td>
<td><b>Export</b> — device, errors, network and logs in one report</td>
</tr>
</table>

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

## Install

The core plus whichever integrations you actually use:

```
flutter pub add devtray
flutter pub add devtray_dio      # and/or devtray_http
flutter pub add devtray_prefs    # and/or devtray_hive, devtray_sqflite
```

Or in `pubspec.yaml`:

```yaml
dependencies:
  devtray: ^0.6.2          # the overlay, the pages, the stores
  devtray_dio: ^0.6.2      # add only what you need
```

Debug tooling belongs in debug builds. `runDebugApp(enabled:)` defaults to `kDebugMode`, so a
release build captures nothing out of the box — see
[the capture switch](packages/devtray#the-capture-switch--release-safety).

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
