# Changelog

## 0.6.0

Context reaches network requests, the overlay can tell which screen the app is on, and your
app can get a callback on anything it captures.

### Added

- **Listeners on every store.** Devtray could only be *read* — the `tick` notifiers say
  "something changed, rebuild", coalesced and with no payload, so acting on a specific
  capture meant diffing a buffer. Each store now hands the item itself back:

  ```dart
  configure: (d) => d
    ..onError((e) => Sentry.captureException(e.error ?? e.message, stackTrace: e.stackTrace))
    ..onResponse((r) { if (r.statusCode == 401) authBloc.add(SessionExpired()); })
    ..onScreen((v) => analytics.screenView(v.name)),
  ```

  `onLog`/`onError`, `onRequest`/`onResponse`/`onFailure`, `onScreen`/`onScreenLeave`,
  `onStateChange`/`onStateError`, `onFreeze`/`onSlowFrame`. `onError` covers every route into
  the log store at once — your own `report` calls, the framework and platform hooks, and
  failed requests — so one registration sees them all. `onFailure` fires regardless of
  `errorReporting`, which governs only whether a failure also becomes a log line.

  **Observe-only.** Listeners run after the item is recorded and cannot change or suppress it.
  One that throws is caught and reported as an error line naming the list it was on, and the
  rest still run: a broken callback should cost you the callback, not the entry it was
  watching, and certainly not the app being debugged.

  The store methods return a disposer for a listener scoped to a widget
  (`final off = DevtrayNet.instance.onFailure(...)`; `off()` in `dispose`) — a returned
  disposer rather than `removeListener(fn)`, since the registration is usually an inline
  closure and there'd otherwise be nothing to pass back.

  `onSlowFrame` is the one to be careful with: it runs inside the frame pipeline and can fire
  every frame on a bad scroll, so a listener doing real work there becomes the jank it is
  measuring.

- **`Devtray.clearListeners()`**, plus `clearLogListeners`, `clearNetworkListeners`,
  `clearNavListeners`, `clearStateListeners` and `clearJankListeners` — for a sign-out that
  should undo whatever the session registered, and for tests, where the stores are singletons
  and a listener left behind fires for every test after it. Blunt by design: they drop
  anything's registrations, so hold the disposer when you only mean to undo your own.
  Unrelated to `enabled`, which stops listeners firing without dropping them.

- **Context on network requests.** Ambient values and enrichers used to reach log lines only,
  so a line could say which screen it came from and a *request* could not — the more useful
  half, since a failing request is usually what you are chasing. Both stores now share one
  `DevtrayContext`, so a single `..enrich('nav', ...)` labels everything.

  Fields appear on the request detail's own **Context** tab, kept away from Request Headers
  and Request Body: there they read as something the app *sent*, where they are the opposite —
  state recorded on the device and transmitted nowhere. Resolved when the request is *made*,
  not when it completes, because a slow request routinely outlives the screen that fired it.

- **`DevtrayNavObserver`** — which screen the app is on, with no call sites:

  ```dart
  MaterialApp(navigatorObservers: [DevtrayNavObserver()], ...)
  ```

  Every log line and request then carries `screen`. An unnamed route reports
  `<unnamed MaterialPageRoute>` rather than silently keeping the previous screen — a field
  that quietly names a page you already left is worse than one that admits it doesn't know.
  `nameOf` derives names yourself.

  A dialog does **not** replace the screen; it adds `overlay` alongside it, so a request fired
  from behind it still says which page it came from. `logNavigation: true` adds a line per
  navigation, off by default because the field already puts the route on every entry.

- **`Devtray.screen(name)`** — for navigation an observer cannot see. An `IndexedStack` or
  `PageView` that swaps its body pushes no route, so nothing can observe it; this is the one
  line at the place that already knows. Both routes feed the same history.

- **A `nav` timeline lane.** Route changes draw as spans rather than marks — "which screen was
  I on at this moment" is an interval question — labelled with the journey (`/ → /settings`,
  `/ ← /settings`) since the same pair of names in the other direction is a different trip.
  Contiguous spans alternate their shading so the joins are visible.

### Fixed

- **A timeline lane with no detail view opened an empty dialog.** The dialog's
  `switch (event.source)` fell through to a `SizedBox.shrink()`, so adding a lane without its
  detail produced a dialog containing literally nothing. The dispatch is now a testable
  function and the fall-through says which type it could not render.

## 0.5.0

`Devtray` is now the one control surface. Switching capture off, opening the panel and hiding
the launcher were three unrelated objects; two of them are gone.

### Breaking

| Was | Now |
|---|---|
| `DevtrayKillSwitch.enabled` | `Devtray.enabled` |
| `DevtrayKillSwitch.addDisableListener` | `Devtray.addDisableListener` |
| `DevtrayController()` + `controller:` | `Devtray.open()` / `.close()` / `.toggle()` |
| `controller.showLauncher.value = x` | `Devtray.showLauncher = x` |
| `runDebugApp(enabled: ...)` | your own `if` around the call |
| `runDebugApp(app: MyApp())` / `appBuilder:` | `runDebugApp(() => MyApp())` |

**`DevtrayController` is gone**, along with `controller:` on `runDebugApp` and
`DevtrayOverlay`. A process has one panel, so its state lives on `Devtray` — nothing to
construct, inject, or thread through your app. This also removes a duplication: `showLauncher`
existed on the widget, on `runDebugApp` *and* on the controller, and the first two were
silently ignored whenever a controller was supplied.

**`runDebugApp(enabled:)` is gone.** It used to make the call a plain `runApp` — no Zone, no
hooks, no overlay. That was real, but the flag could only be read *after* the capture Zone and
the error hooks were installed, so `enabled: false` still left a Zone wrapping your app,
`debugPrint` replaced and `FlutterError.onError` replaced. Keeping devtray out of a build is
now your own `if`, which is total in a way the flag never was:

```dart
void main() {
  if (kDebugMode) {
    runDebugApp(() => const MyApp(), pages: [...]);
  } else {
    runApp(const MyApp());
  }
}
```

`Devtray.enabled` still defaults to `kDebugMode`, so a release build that *does* call
`runDebugApp` records nothing.

**`app` and `appBuilder` are now one positional builder.** Two parameters, exactly one of
which had to be passed, enforced by an assert that fired at runtime:

```dart
runDebugApp(() => const MyApp(), pages: [...]);
```

Positional because it is the one argument every call has, and it mirrors `runApp(MyApp())`.
A builder because the old `app:` widget was constructed at the *call site* — before
`runDebugApp` was even entered — so an app whose tree read something `setup` initialised threw
before the bootstrap ran, and the fix was to notice and switch parameters. Now the tree is
always built after `setup`, and the failure mode is gone rather than documented.

### Added

- **`configure: (d) => d..launcher(false)`** — the launcher's visibility alongside everything
  else you configure, and **`..openOnStart()`** to open the panel at launch, for iterating on a
  page inside the overlay itself.

### Fixed

- **`runDebugApp` never forwarded `enabled` to the overlay it built**, so
  `runDebugApp(enabled: true)` in a release build gave you capture on and the UI silently off —
  the exact drift the flag's own documentation claimed to prevent. Moot now that the flag is
  gone, but it was wrong for two releases.
- **`DevtrayJank` kept running after capture was switched off.** Alone among the stores it
  registered no disable-listener, so its heartbeat timer and frame callback — the one
  steady-state cost in the package — survived a switch-off with its buffers intact.
- **The tools panel could throw during teardown.** `DebugToolsScreen`'s `TabController` was a
  lazy `late` field, and `dispose()` was its first read whenever the panel was closed without
  anyone touching a tab — constructing a controller at a point where the ancestor lookup its
  ticker needs is illegal.

## 0.4.0

Setup used to be spread across three mechanisms — arguments to `runDebugApp`, mutating
singletons, and imperative `start()` calls — in an order nobody stated. This release gives
it one place, and renames the stores so a call site says which tool it belongs to.

### Breaking

Every rename is mechanical; the behaviour is unchanged.

| Was | Now |
|---|---|
| `Devtray` (the widget) | `DevtrayOverlay` |
| `LogStore` | `DevtrayLog` |
| `NetworkLogStore` | `DevtrayNet` |
| `StateInspector` | `DevtrayState` |
| `MockStore` | `DevtrayMocks` |
| `LogExporter` | `DevtrayExport` |
| `FreezeWatchdog` | `DevtrayJank` |

`Devtray` is now the configuration facade and the shorthand for logging, which is why the
widget had to move aside. A find-and-replace on whole words covers the rename; the analyzer
finds anything missed.

**Why rename at all.** `LogStore.instance.log(...)` reads like a generic utility that
happens to be in scope. Someone reading unfamiliar code should be able to tell where a log
line goes, and every new name is *shorter* than the one it replaces.

### Added

- **`configure:` on `runDebugApp`** — one place for every store setting:

  ```dart
  runDebugApp(
    app: const MyApp(),
    configure: (devtray) => devtray
      ..excludeUrls(['/health'])
      ..context({'build': '1.4.2'})
      ..inspect<CartCubit>((c) => {'items': c.items.length})
      ..detectFreezes(),
  );
  ```

  It runs after the kill switch is set and the capture hooks are installed, and before your
  `setup` bootstrap. That ordering is the point: configuring a store *before* the kill switch
  silently does nothing, which was easy to hit when setup was scattered. It is skipped
  entirely when `enabled` is false, so anything expensive inside it costs a release build
  nothing.

  Covers every tunable on every store, with `raw(() { ... })` for anything it doesn't — a
  missing convenience method must never be a reason to configure something outside the
  callback and lose the guarantee. A test asserts the full surface and fails when a new knob
  is added without a route to it.

- **`Devtray.log` / `.report` / `.setContext` / `.withContext`** — statics for the call sites
  an app hits constantly. `Devtray.log('signed in')` rather than
  `DevtrayLog.instance.log('signed in')`. The stores stay public for everything else.

- **`logToAsync`** — for sinks that must be opened asynchronously, like a file sink that
  creates a directory. `runDebugApp` awaits it before running your app, so lines logged
  during bootstrap still reach the sink. A sink that fails to open is reported into the log
  and skipped, rather than taking down the launch of the app it exists to observe.

- **`inspectAll`** — several typed extractors in one call:

  ```dart
  ..inspectAll([
    Inspect<CartCubit>((c) => {'items': c.items.length}),
    Inspect<Session>((s) => {'signIns': s.signIns}),
  ])
  ```

  Each entry is an `Inspect<T>` rather than a bare callback because the registry is keyed by
  the source type — a list of plain functions would erase it. `inspect<T>` is unchanged and
  still right for a single one.

## 0.3.0

The Timeline page, and UI-freeze detection. No breaking changes.

### Added

- **`TimelineDebugPage`** — requests, logs and state changes on one shared time axis. Every
  other page answers "what happened to *this*"; this one answers "what just happened", which
  is the question you have when a screen breaks and you don't yet know which subsystem to
  blame.

  It owns no data. Every store already timestamps its entries, so this is a view over the
  three existing stores rather than a fourth to keep in sync, and it costs nothing until you
  open it. Requests draw as bars (they have duration), logs and state as marks. Tapping
  anything opens the same detail dialog its owning page would show.

  Live-following by default; any drag pauses it. Pan by dragging or with step buttons, zoom
  from 200ms to 10 minutes on a logarithmic slider. Zoom survives the live/paused toggle —
  the reset button is the explicit way back to the default.

- **`DevtrayJank`** — detects periods where the UI isolate stopped responding, and frames
  that rendered too slowly, drawn as a fourth lane on the timeline. **Opt-in** via
  `TimelineDebugPage(detectFreezes: true)` or `DevtrayJank.instance.start()`, because it
  is the only capture in the overlay with a real steady-state cost.

  Detection is **retrospective and cannot be otherwise**: a blocked isolate runs no timer,
  frame callback or microtask, including the one watching it. So a freeze is reported once it
  ends, a terminal hang is reported by nothing, and there is no stack trace — by the time the
  gap is measurable, whatever caused it has returned. Tapping a freeze instead shows what
  else was happening in that window, which the dialog labels as circumstantial rather than
  implying a cause it cannot prove.

  Both a heartbeat and `addTimingsCallback` are used, because neither is sufficient alone:
  the timings callback only fires for frames that *rendered*, so a three-second block
  produces no timings at all.

- `JumpToLatestButton` moved to `widgets/` and is now exported — the Logs and Network pages
  share it rather than each carrying a copy.

## 0.2.0

Performance, log persistence, and structured log context.

### Breaking

**`Devtray.enabled` now defaults to `kDebugMode` instead of `true`.**

The stores already refused to record in release builds, so the one thing that survived
into production was the floating bug button. If you deliberately ship the overlay in a
release flavour (staging, dogfood), pass it explicitly:

```dart
Devtray(enabled: true, child: MyApp());   // was the default; now opt-in
```

`runDebugApp(enabled: ...)` is unaffected — it always required the argument.

### Added

- **Log persistence.** `LogSink` is the shape of a destination and `DevtrayExport` owns the
  batching; nothing happens until you add a sink. Entries reach the sinks *before* the
  ring buffer evicts, so a long session writes every line even though the page shows the
  last 1000. `FlushPolicy` is a choice — `immediate()` / `batched()` / `manual()` — with
  `flushOnPause` to catch backgrounding. See the new
  [`devtray_log_file`](https://pub.dev/packages/devtray_log_file) for files; a remote
  uploader is just another `LogSink`.
- **Saved session browser.** `LogsDebugPage(sessionSource: ...)` adds a picker for past
  runs, opened read-only and clearly marked as not live. Loaded sessions are held
  separately from `DevtrayLog` and never re-exported.
- **Structured context on log entries.** Three layers, composing least-specific to most:
  `DevtrayLog.setContext` (ambient), `addEnricher` (computed per entry), and `fields:` on
  the individual call — plus `withContext` for a scope. All land in `LogEntry.fields`,
  are searchable and filterable, and are written by the sinks. Costs nothing when unused.
- `JumpToLatestButton`, `LogFieldsSection`, `NetworkLogRow` and `DebugStorageAdapter.notice`
  are now exported.

### Fixed

- **The overlay no longer taxes the host app's frames.** Dragging the launcher called
  `setState` on the widget wrapping your entire app, once per pointer move, and there was
  no `RepaintBoundary` anywhere — so every drag frame repainted the app behind it. Both
  layers are now behind boundaries and the app sits outside every builder.
- **The Logs and Network lists stay still while you read them.** A scrolled-back reader
  no longer drifts as entries arrive or are evicted.
- **Opening a full buffer is no longer slow.** Both lists now declare `itemExtent` (rows
  are a fixed height), so the viewport computes scroll geometry arithmetically instead of
  laying out every row. Logs: 2197ms → 485ms with 1000 entries. Network frame cost:
  ~37ms → ~23ms.
- Search is debounced, and `LogEntry.searchable` is computed once rather than rebuilt per
  entry per keystroke.
- Response bodies are capped (`DevtrayNet.maxBodyChars`, default 256KB), the HTML
  sniff no longer stringifies whole bodies on every rebuild, and `prettyJson` is memoised.
- State history no longer holds large state objects strongly — non-primitives are
  snapshotted at capture time. `DevtrayState.retainStateObjects` opts back in.
- The Storage page reads only the selected adapter, refreshes only what was mutated, and
  caps sqflite reads at `maxRows` with the truncation surfaced.
- `DevtrayNet` and `DevtrayState` now coalesce their change notifications, matching
  `DevtrayLog`.
- The dio interceptor detects double-registration (which used to orphan an entry as
  permanently pending); the Riverpod and bloc observers check the kill switch before doing
  work that throws-and-catches per provider update in release.

## 0.1.0

**The core now has no dependencies beyond Flutter.** Every integration moved to its own
package, so an app compiles only what it uses — a Riverpod + `http` app no longer pulls in
dio, bloc, `shared_preferences`, `device_info_plus`, `package_info_plus` and `flutter_html`
to get a debug overlay.

The **pages** all stayed in the core. Only the adapters moved: `NetworkDebugPage` reads from
a transport-agnostic store, so dio and http still feed the same page.

### Breaking

1. **Adapters moved out.** Add the package and import it:

   | Was in `devtray` | Now in |
   |---|---|
   | `DebugDioInterceptor` | `devtray_dio` |
   | `DebugHttpClient` | `devtray_http` |
   | `DebugBlocObserver` | `devtray_bloc` |
   | `SharedPreferencesStorageAdapter`, `SharedPreferencesMockRuleStorage` | `devtray_prefs` |
   | `PluginDeviceInfoProvider` | `devtray_device` |
   | `HtmlPreviewDialog` | `devtray_html` |

2. **`runDebugApp(persistMockRules:)` is gone.** Setting a storage backend is the opt-in.

   Mock rules are session-only until you install one — and they'll stop surviving hot
   restart silently, which is exactly when you're iterating on an error state. To restore
   the old behaviour:

   ```dart
   // + devtray_prefs
   DevtrayMocks.instance.storage = SharedPreferencesMockRuleStorage();
   ```

   The flag was a second switch that could only ever disagree with the first: `storage`
   defaults to in-memory, which is always empty at startup, so restoring from it was already
   a no-op.

3. **`NetworkDebugPage(enableMocking:)` is gone.** `DevtrayMocks.instance.disable()` is the one
   switch — the page reads it and drops the whole mocking UI along with the interception.

   Two switches meant they could disagree, and the dangerous direction was silent: hiding the
   UI while a rule added from code went on faking traffic, with nothing on screen to reveal
   it. That state is now unrepresentable.

4. **The Network page's HTML preview button is hidden unless you supply a previewer.**

   The core can't render HTML any more, so a button would open nothing:

   ```dart
   // + devtray_html
   NetworkDebugPage(onPreviewHtml: HtmlPreviewDialog.show)
   ```

   `onPreviewHtml` is a plain `void Function(BuildContext, String)` — pass your own renderer
   if you'd rather.

### Added

* `DebugHtmlPreviewer` — the hook type behind `NetworkDebugPage.onPreviewHtml`.

## 0.0.1

* Initial release.
