# Changelog

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

- **`FreezeWatchdog`** — detects periods where the UI isolate stopped responding, and frames
  that rendered too slowly, drawn as a fourth lane on the timeline. **Opt-in** via
  `TimelineDebugPage(detectFreezes: true)` or `FreezeWatchdog.instance.start()`, because it
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

- **Log persistence.** `LogSink` is the shape of a destination and `LogExporter` owns the
  batching; nothing happens until you add a sink. Entries reach the sinks *before* the
  ring buffer evicts, so a long session writes every line even though the page shows the
  last 1000. `FlushPolicy` is a choice — `immediate()` / `batched()` / `manual()` — with
  `flushOnPause` to catch backgrounding. See the new
  [`devtray_log_file`](https://pub.dev/packages/devtray_log_file) for files; a remote
  uploader is just another `LogSink`.
- **Saved session browser.** `LogsDebugPage(sessionSource: ...)` adds a picker for past
  runs, opened read-only and clearly marked as not live. Loaded sessions are held
  separately from `LogStore` and never re-exported.
- **Structured context on log entries.** Three layers, composing least-specific to most:
  `LogStore.setContext` (ambient), `addEnricher` (computed per entry), and `fields:` on
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
- Response bodies are capped (`NetworkLogStore.maxBodyChars`, default 256KB), the HTML
  sniff no longer stringifies whole bodies on every rebuild, and `prettyJson` is memoised.
- State history no longer holds large state objects strongly — non-primitives are
  snapshotted at capture time. `StateInspector.retainStateObjects` opts back in.
- The Storage page reads only the selected adapter, refreshes only what was mutated, and
  caps sqflite reads at `maxRows` with the truncation surfaced.
- `NetworkLogStore` and `StateInspector` now coalesce their change notifications, matching
  `LogStore`.
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
   MockStore.instance.storage = SharedPreferencesMockRuleStorage();
   ```

   The flag was a second switch that could only ever disagree with the first: `storage`
   defaults to in-memory, which is always empty at startup, so restoring from it was already
   a no-op.

3. **`NetworkDebugPage(enableMocking:)` is gone.** `MockStore.instance.disable()` is the one
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
