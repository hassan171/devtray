# debug_overlay

An in-app debugging overlay for Flutter: a draggable floating button that opens a tabbed
tools panel over your running app.

Seven built-in pages — **Network** (with mocking), **Logs** (errors folded in), **State**,
**Storage**, **Visual**, **Device** and **Export** — and every other tab is one you add.

You decide **whether** it exists, **when** it opens, and **how** it's presented.

---

## Install

The core has **no dependencies** beyond Flutter itself. Every integration — dio, http,
bloc, `shared_preferences`, device info, HTML preview — is a separate package, so you only
compile the ones you use:

```yaml
dependencies:
  debug_overlay: ^0.1.0          # the overlay, the pages, the stores

  # Add only what you need:
  debug_overlay_dio: ^0.1.0       # DebugDioInterceptor
  debug_overlay_http: ^0.1.0      # DebugHttpClient
  debug_overlay_bloc: ^0.1.0      # DebugBlocObserver     → the State page
  debug_overlay_riverpod: ^0.1.0  # DebugRiverpodObserver → the State page
  debug_overlay_prefs: ^0.1.0     # SharedPreferences adapter + mock persistence
  debug_overlay_hive: ^0.1.0      # browse and edit Hive boxes
  debug_overlay_sqflite: ^0.1.0   # every SQLite table, discovered from the schema
  debug_overlay_device: ^0.1.0    # real device/OS/app facts
  debug_overlay_html: ^0.1.0      # preview HTML response bodies
```

A Riverpod app that uses `package:http` takes `debug_overlay`,
`debug_overlay_http` and `debug_overlay_riverpod` — and never compiles dio or
bloc.

The integrations are **additive**, not alternatives: install `_bloc` and
`_riverpod` together and both fill the same State page — useful precisely when
you're migrating between them. Same for `_dio` and `_http`.

The **pages** all live in the core: it's only the adapters that move. `NetworkDebugPage`
reads from a transport-agnostic store, so dio and http feed the same page; `StateDebugPage`
reads from a library-agnostic inspector, so bloc is just one way to fill it.

## Quick start

Swap `runApp` for `runDebugApp` and list the pages you want. That's the whole setup:

```dart
import 'package:debug_overlay/debug_overlay.dart';
import 'package:debug_overlay_dio/debug_overlay_dio.dart';
import 'package:debug_overlay_device/debug_overlay_device.dart';

final dio = Dio()..interceptors.add(DebugDioInterceptor());

void main() => runDebugApp(
  app: const MyApp(),
  enabled: kDebugMode,
  pages: const [
    NetworkDebugPage(),
    LogsDebugPage(), // logs + errors in one filterable stream
    DeviceDebugPage(provider: PluginDeviceInfoProvider()),
  ],
);
```

Every request through that `dio` now shows up in the overlay, along with your logs, any
uncaught errors, and the device's specs. Nothing else to wire up — no wrapper widget, no
second `enabled` flag to keep in sync.

`runDebugApp` installs the log/error capture *and* wraps your app in the overlay. With
`enabled: false` it is exactly `runApp(app)`: no Zone, no hooks, no overlay in the tree —
so it's safe to leave in a release build.

It takes every option `DebugOverlay` does — `presentation`, `theme`, `controller`,
`showLauncher`, the launcher's corner/size/icon. See
[Controlling when and how it opens](#controlling-when-and-how-it-opens).

### Already have a bootstrap?

`runDebugApp` takes a `setup` callback, run **inside** the capture Zone and awaited before the
first frame — so your Firebase init, your dotenv load, and anything they log or throw are all
captured:

```dart
void main() => runDebugApp(
  app: const MyApp(),
  enabled: kDebugMode,
  setup: () async {
    await Firebase.initializeApp();
    await MyDotEnv.init();
  },
  pages: const [...],
);
```

If your app widget can only be built *after* that (it reads something the bootstrap produced),
pass `appBuilder:` instead of `app:` — it's called once `setup` finishes.

### If you can't hand over `runApp`

Add-to-app, or a host that owns `main`. Then wire the two halves yourself:

```dart
void main() => runZonedGuarded(
  () {
    WidgetsFlutterBinding.ensureInitialized();   // must be INSIDE the Zone
    captureErrors();                             // framework + platform errors
    captureDebugPrint();                         // debugPrint

    runApp(DebugOverlay(pages: const [...], child: const MyApp()));
  },
  (error, stack) => LogStore.instance.report(error, stackTrace: stack, source: ErrorSource.uncaught),
  zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {          // bare print()
      LogStore.instance.log(line);
      parent.print(zone, line);
    },
  ),
);
```

They're separate because the Zone has to be installed *around* `runApp`, and `DebugOverlay` is
a widget that only exists inside it — a widget can't wrap its own `runApp` call.

If you can't own `runApp` at all, call `captureErrors()` and `captureDebugPrint()` anywhere
during startup. You'll still get `debugPrint` and framework errors; you'll miss bare `print()`
and uncaught async errors, which genuinely require the Zone.

---

## Network

The overlay reads from a single transport-agnostic sink, `NetworkLogStore`. Three ways in:

**dio** — add the interceptor **last**, so it sees the final headers other interceptors set:

```dart
dio.interceptors.add(DebugDioInterceptor());
```

**package:http** — wrap any `Client`. Since it's a `BaseClient`, it also drops into anything
that accepts one (Supabase, generated OpenAPI clients, …):

```dart
final client = DebugHttpClient(http.Client());
await client.get(Uri.parse('https://api.example.com/users'));
```

**Anything else** — drive the store by hand. This is the whole API:

```dart
final entry = NetworkLogStore.instance.add(
  method: 'GET',
  uri: uri,
  requestHeaders: headers,
  requestBody: body,
);

// ...later, when the response lands (entry is null if the URL was excluded):
NetworkLogStore.instance.complete(
  entry!.id,
  status: NetworkLogStatus.success,
  statusCode: 200,
  responseHeaders: {'content-type': ['application/json']},
  responseBody: json,
);
```

Keep noisy background traffic out of the list:

```dart
NetworkLogStore.instance
  ..excludedUrlPatterns.addAll(['/health', '/log-error'])
  ..maxEntries = 300;   // default 500, oldest dropped first
```

Attach transport-specific context as its own detail tab:

```dart
NetworkLogStore.instance.attachExtra(entry.id, 'Proxy JS', generatedJs);
```

**Per request you get:** method, URL, status, duration, request/response headers and bodies
(pretty-printed JSON), query params, error message, and **copy-as-cURL**. Multipart bodies
are snapshotted and rendered as `-F` flags in the cURL.

### Previewing an HTML response

A server-rendered error page or an SSO redirect is easier to read rendered than as markup.
Rendering HTML needs a real parser, though, and that's a dependency most apps shouldn't carry
for one button — so it's opt-in:

```yaml
dependencies:
  debug_overlay_html: ^0.1.0
```

```dart
NetworkDebugPage(onPreviewHtml: HtmlPreviewDialog.show)
```

Without a previewer the button isn't drawn. `onPreviewHtml` is just a
`void Function(BuildContext, String)`, so you can pass your own renderer instead.

---

## Mocking

Mocking turns the network inspector from an observer into a **test harness**. Force a
response, inject latency, or kill the network — reaching app states that would otherwise need
a server-side change.

It's not a separate tab: the **Mocks** button in the Network tab's toolbar opens the mocking
UI in-place (a back arrow returns to the request list). So registering the Network page is all
you need:

```dart
pages: const [NetworkDebugPage()],
```

Nothing else to wire up: the dio and http adapters already consult the rules. To drop mocking
entirely, call `MockStore.instance.disable()` — that stops the interception *and* takes the
whole UI with it. See [Don't want mocking at all?](#dont-want-mocking-at-all).

### The workflow that matters

Don't author JSON from scratch on a phone. Instead: **fire the real request, open it on the
Network page, and hit "Mock this request."** The rule is prefilled with its real URL, method,
status and response body — so you *edit* rather than write. Take a 200 and make it a 500;
take a list and make it empty.

(The seeded pattern is the URL **path**, not the full URL — a rule keyed to the host would
break the moment you point the app at a different environment.)

### Actions

| Action | What happens |
|---|---|
| **Fake response** | Return a canned status + body. The server is never contacted. |
| **Fail (offline)** | Throw a connection error, as if the network were unreachable. |
| **Delay only** | Still hits the real server — just late. Surfaces loading states and races. |

Plus two master switches: **Simulate offline** (fail everything; overrides all rules) and
**Apply rules** (park every rule without deleting them).

### Nothing is silently faked

A mocked response that looks identical to a real one will cost you an afternoon. So:

- Mocked rows are badged **MOCKED** in the request list.
- A **warning banner** appears on both the Network and Mocks pages whenever anything is
  intercepting, with a one-tap "Turn off".
- The request detail gets a *Mocked* tab spelling out that the server was never contacted.

### Matching

Substring on the URL by default (`/orders`). Flip the **Regex** switch on a rule for
`r'/users/\d+/orders$'`. An invalid regex simply never matches — a half-typed pattern in the
editor can't take down every request in flight.

**First enabled rule wins**, so order matters: a specific rule must sit above a broad one.

### From code

The UI is a front-end for a plain store, so you can drive it from a test or a script:

```dart
MockStore.instance.offline.value = true;               // kill the network

MockStore.instance.add(MockRule(
  id: MockStore.instance.nextId(),
  urlPattern: '/orders',
  method: 'POST',
  statusCode: 500,
  body: '{"message": "boom"}',
  delay: const Duration(milliseconds: 800),
));
```

### Persistence

Rules are **session-only by default** — they're gone on a hot restart. Two lines make them
survive, and they're worth adding if you use mocks at all: otherwise you re-add "force
/orders to 500" every time, which is exactly when you're iterating on an error state.

```yaml
dependencies:
  debug_overlay_prefs: ^0.1.0
```

```dart
MockStore.instance.storage = SharedPreferencesMockRuleStorage();
```

That's the whole opt-in — setting a backend *is* the switch, so there's no flag to keep in
sync with it. It's opt-in at all because persistence means a real storage package, and the
core doesn't depend on `shared_preferences` — no app should carry that for a debug tool it may
not use.

Only the rules are stored (a small JSON blob); no logs, no request bodies, so none of the PII
concerns that make persisting the *data* a bad idea. Swap the backend by implementing
`MockRuleStorage` and setting `MockStore.instance.storage` — that's the same seam
`debug_overlay_prefs` uses.

### Don't want mocking at all?

One line, and it's the real one:

```dart
MockStore.instance.disable();
```

That stops the adapters intercepting — it beats offline mode, every rule, and skips restoring
persisted rules on the next launch. The Network page reads it too, so the Mocks button, "Mock
this request" and the interception warning all disappear with it.

There's deliberately no separate flag for the UI. There used to be, and it was a trap: hiding
the affordances while the adapters went on consulting `MockStore` meant a rule added **from
code** could fake traffic with nothing on screen to reveal it. One switch, so the two can't
disagree.

---

## Visual

`VisualDebugPage` exposes Flutter's rendering debug flags as switches — the on-device
substitute for a tethered DevTools session.

```dart
pages: [VisualDebugPage()],
```

| Toggle | What it shows |
|---|---|
| **Paint layout bounds** | Outlines every box. The fastest way to see why something is the wrong size. |
| **Repaint rainbow** | Recolours a layer each time it repaints. A patch that keeps flashing is repainting every frame — usually a missing `const` or `RepaintBoundary`. |
| **Paint baselines** | Text baselines, for when text sits a pixel off from what it should align with. |
| **Highlight taps** | Flashes the area that got the pointer event — shows what *actually* received the tap. |
| **Slow animations** | Runs every animation at 1/5 speed so you can see what a transition does. |

> **Not included: layer borders.** `debugPaintLayerBordersEnabled` only draws when a layer
> records a *new* picture, not on every repaint — so layers with a cached picture never show
> it, and the toggle silently does nothing from inside the app. DevTools can do it because it
> drives the engine directly. Use DevTools for that one.

These are **process-wide globals** and stay on after you close the overlay — a repaint
rainbow left running looks exactly like a rendering bug. So the page shows a warning banner
whenever any flag is on, with a one-tap **Reset all**.

Add your own toggles, or trim the list:

```dart
VisualDebugPage(flags: [
  ...kDefaultVisualDebugFlags,
  VisualDebugFlag(
    label: 'Show grid overlay',
    description: 'My app-specific debug grid',
    get: () => myGridEnabled,
    set: (v) => myGridEnabled = v,
  ),
])
```

---

## Export

`ExportDebugPage` bundles device + errors + network + logs into one plain-text bug report.
Turns "it broke on my phone" into an actual report.

```dart
pages: [
  const ExportDebugPage(
    deviceInfoProvider: PluginDeviceInfoProvider(),   // optional device section
    // optional — the package takes no share dependency of its own:
    // onShare: (report) => Share.share(report),      // package:share_plus
  ),
],
```

Pick which sections to include, **preview the whole thing**, then copy it — or hand it to the
OS share sheet via `onShare`.

> **The report is verbatim.** Headers, auth tokens, request and response bodies all go in
> exactly as captured — that's what makes it worth reading, and what lets you replay a request
> from it. Nothing is scrubbed, so look at the preview before you send it anywhere.

Need it without the UI?

```dart
final report = DebugReport.build();   // → String
```

---

## Storage

`StorageDebugPage` browses — and **edits** — key/value storage while the app is running. Flip
a feature flag, expire a token, clear an onboarding-seen bool, without rebuilding.

```dart
pages: const [
  StorageDebugPage(adapters: [SharedPreferencesStorageAdapter()]),
],
```

### Types are preserved

This is the safety story. `SharedPreferences` has a setter *per type* and throws on the next
**read** if you wrote the wrong one — so an editor that turned every value into a String would
be a landmine. Instead the control matches the value's existing type, and writes that type
back:

| Stored type | Editor | Bad input |
|---|---|---|
| `bool` | a switch | impossible |
| `List<String>` | **chips** — tap to rename, ✕ to remove, `+` to add | impossible |
| `int` / `double` | number field | rejected — *"Not an int"*, nothing written |
| `String` | text field | anything goes |

A rejected edit leaves the store **untouched**.

Bools and lists write straight through — the switch and the chips *are* the editor. Scalars use
an Edit → Save step.

Lists are chips rather than a JSON text area on purpose: hand-editing `["flutter","dart"]` on a
phone is miserable, and it made *"Invalid JSON"* a failure you could hit by mistyping a bracket.
Manipulating each element directly makes a malformed list **unrepresentable**. Renaming a chip to
empty removes it.

### Other backends: Hive, secure storage, your own

Implement `DebugStorageAdapter` — about 15 lines. No dependency is added to the package, and
it works with **typed and encrypted** boxes, which a generic Hive adapter couldn't:

```dart
class SettingsBoxAdapter extends DebugStorageAdapter {
  @override
  String get name => 'Settings (Hive)';

  @override
  Future<Map<String, Object?>> readAll() async {
    final box = Hive.box<String>('settings');   // already open, keys already decrypted
    return {for (final k in box.keys) k.toString(): box.get(k)};
  }

  @override
  Future<void> write(String key, Object? value) async =>
      Hive.box<String>('settings').put(key, value! as String);

  @override
  Future<void> delete(String key) async => Hive.box<String>('settings').delete(key);
}
```

Then: `StorageDebugPage(adapters: [const SharedPreferencesStorageAdapter(), SettingsBoxAdapter()])`

Override `writable => false` for a store you only want to look at — the page hides its edit and
delete controls for that section entirely. An adapter that throws on
`readAll` shows its error inline; the other sections still render.

---

## Logs

`LogsDebugPage` shows captured log output, filterable by level and tag, searchable, with the
whole filtered view copyable as plain text for a bug report.

**What gets captured depends on how you start the app:**

| | `debugPrint` | framework errors | bare `print()` | uncaught async errors | `dart:developer` `log()` |
|---|---|---|---|---|---|
| `runDebugApp(...)` | ✅ | ✅ | ✅ | ✅ | ❌ — see below |
| `captureErrors()` + `captureDebugPrint()` | ✅ | ✅ | ❌ | ❌ | ❌ — see below |

Bare `print()` and uncaught async errors can only be intercepted from inside a custom `Zone`,
which means owning the `runApp` call. If you'd rather not, call `captureErrors()` and
`captureDebugPrint()` anywhere during startup and accept the two gaps. Nothing is ever
swallowed — logs still print and errors still reach the console and the red error screen.

Each capture channel is a separate switch on `runDebugApp`, all on by default —
`captureFlutterErrors`, `captureDebugPrints`, `captureZonePrints`, `captureUncaughtErrors`.
Turn one off when your app already forwards that channel itself and you'd otherwise
double-report. There's also `onUncaughtError` if you want to forward the Zone's errors to your
own crash reporter.

### `dart:developer`'s `log()` is never captured — and can't be

Every channel above is hooked by grabbing a Dart-level indirection point: `print` has a
`ZoneSpecification` entry, `debugPrint` is a reassignable global, `FlutterError.onError` is an
assignable handler. **`developer.log` has none of those** — it's declared `external` in the SDK
and implemented natively, emitting straight to the VM service protocol for DevTools' Logging
view. There is nothing to install a hook on, by any package.

So it's bridged at the call site instead. This package exports a drop-in with the identical
signature — change the import, and every existing `log(...)` call keeps compiling:

```dart
// import 'dart:developer';
import 'package:debug_overlay/debug_overlay.dart';

log('user signed in', name: 'auth', level: 800);   // DevTools *and* the Logs page
```

`name` becomes the entry's tag, `level` maps onto `LogLevel` via the `package:logging` scale
(FINE 500 / INFO 800 / WARNING 900 / SEVERE 1000) that `developer.log` documents. The real
`developer.log` is still called, so DevTools is unaffected. If `log` collides with something in
scope (`dart:math` exports one too), use `debugLog` — same function, unambiguous name.

### Hooking in your own logger

If you already use `logger`, `talker`, `logging`, or something homegrown, keep it. The page
reads from `LogStore` and nothing else, so bridging is one call:

```dart
LogStore.instance.log(
  'User signed in',
  level: LogLevel.info,
  tag: 'auth',
  error: someError,       // optional
  stackTrace: someStack,  // optional
);
```

Use `debugLevelFromName('SEVERE')` / `debugLevelFromSeverity(1000)` to map a foreign level
onto `LogLevel` — they understand the aliases the common packages use (`severe`, `wtf`,
`warn`, `finest`, …).

**package:logger** — add an output alongside your console one, and your existing setup is
untouched:

```dart
class DebugOverlayLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) => LogStore.instance.log(
    event.lines.join('\n'),
    level: debugLevelFromName(event.level.name),
  );
}

final logger = Logger(output: MultiOutput([ConsoleOutput(), DebugOverlayLogOutput()]));
```

**package:logging**

```dart
Logger.root.onRecord.listen((r) => LogStore.instance.log(
  r.message,
  tag: r.loggerName,
  level: debugLevelFromName(r.level.name),
  error: r.error,
  stackTrace: r.stackTrace,
));
```

**talker**

```dart
talker.stream.listen((d) => LogStore.instance.log(
  d.message ?? '',
  level: debugLevelFromName(d.logLevel?.name),
  tag: d.title,
  error: d.exception ?? d.error,
  stackTrace: d.stackTrace,
));
```

See `lib/src/logs/log_bridge.dart` for these snippets in-source.

---

## Errors

There's no separate Errors tab — errors are folded into the **Logs page** as error-level
rows. Expand one for the full report: the exception, the widget-ownership context, and either
the failed request/response (network errors) or the Dart stack trace, with a one-tap "copy
report". Filter the Logs page to `Level = ERR`, or `Source = flutter / uncaught / network /
reported`, and you have an errors-only view without leaving the stream.

The point is the errors **nobody was watching the console for** — so the launcher grows a red
count badge when errors arrive, and opening the Logs page clears it:

```dart
DebugOverlay(showErrorBadge: false, ...)   // if you'd rather it didn't
```

Report your own caught errors — they show up as error rows just the same:

```dart
try {
  await risky();
} catch (e, s) {
  LogStore.instance.report(e, stackTrace: s);
  rethrow;
}
```

There is **one store**: `LogStore` holds ordinary logs and errors alike. An error is just an
error-level entry carrying the extra report fields (`source`, context, stack) — `report()`
records it and bumps the badge; there's no separate error store or tab.

### Failed requests land here too

A failed request is an error, so the Network page forwards failures into the same stream —
which means a dead backend badges the launcher instead of waiting for you to think to open
the Network tab. The expanded error row shows the request, response headers and response body
(a transport failure has no meaningful Dart stack, so the request itself is the diagnostic).

By default **every failure is forwarded** (`all`). If routine 4xx get in the way — a 404 on a
"does this exist?" probe, a 401 that kicks off a token refresh — pass a narrower mode to the
Network page:

```dart
NetworkDebugPage(errorReporting: NetworkErrorReporting.serverAndTransport)  // skip 4xx
NetworkDebugPage(errorReporting: NetworkErrorReporting.none)                // stop forwarding
```

| Mode | Forwards |
|---|---|
| `none` | nothing — failures stay on the Network page |
| `serverAndTransport` | 5xx + transport failures (timeout, refused connection, bad cert) |
| `all` *(default)* | every failed request, 4xx included |

The page sets this when it builds; you can still override it live from code at any time via
`NetworkLogStore.instance.errorReporting.value = ...`.

URLs in `excludedUrlPatterns` never reach either page.

---

## Device

`DeviceDebugPage` shows device model, OS, app version, and live screen metrics (size, DPR,
orientation, text scale, safe area, locale) — the things you always end up asking for in a
bug report. The whole page copies out as one block.

The default provider needs no plugins but only knows the build mode and platform. For real
device facts, use `PluginDeviceInfoProvider` (backed by `device_info_plus` and
`package_info_plus`), and merge in your own sections:

```dart
DeviceDebugPage(
  provider: CompositeDeviceInfoProvider([
    const PluginDeviceInfoProvider(),
    StaticDeviceInfoProvider([
      DeviceInfoSection('Environment', {'API': apiUrl, 'Flavor': flavor}),
      DeviceInfoSection('Session', {'User': user.id, 'Role': user.role}),
    ]),
  ]),
)
```

Implement `DeviceInfoProvider` for anything dynamic. The screen section is always appended by
the page itself, read live from the `MediaQuery`, so it stays correct across rotation.

---

## Adding your own pages

A page is a tab. Inline:

```dart
DebugOverlay(
  pages: [
    const NetworkDebugPage(),
    DebugPage.builder(
      title: 'Env',
      icon: Icons.settings,
      builder: (context) => const MyEnvPage(),
    ),
  ],
  child: ...,
)
```

Or subclass, when the page needs its own logic:

```dart
class LogsPage extends DebugPage {
  const LogsPage();

  @override
  String get title => 'Logs';

  @override
  IconData? get icon => Icons.article;

  @override
  Widget build(BuildContext context) => const LogsView();
}
```

To make your page look native to the overlay, reuse its widgets — all exported:
`CopyableSection`, `CopyButton`, `DebugTabBar`, `DebugSearchBar`,
`DebugTextStyles.debugMono(...)` for anything machine-produced, and
`DebugOverlayTheme.of(context)` for colors.

---

## Controlling when and how it opens

### The controller — open it from anywhere

```dart
final debug = DebugOverlayController();

DebugOverlay(controller: debug, pages: [...], child: ...);

// From a shake detector, a 5-tap on the logo, a hidden settings row, a test:
debug.open();
debug.close();
debug.toggle();
```

### Hide the floating button and use your own

The draggable button is on by default, but it's just *a* way in — not the only one. Hide it
and trigger the overlay from anywhere you like:

```dart
final debug = DebugOverlayController(showLauncher: false);   // hidden from the start

void main() => runDebugApp(const MyApp(), controller: debug, pages: [...]);

// …then anywhere in your app:
IconButton(onPressed: debug.open, icon: const Icon(Icons.bug_report))
```

Your trigger can be anything — an AppBar action, a row in a hidden settings screen, a 5-tap
on the logo, a shake detector, a keyboard shortcut. Just call `debug.open()`.

Toggle it at runtime too:

```dart
debug.showLauncher.value = false;   // hide
debug.showLauncher.value = true;    // show
```

That's how you ship a build with **no visible debug affordance** but a secret way in.

> Note: `runDebugApp(showLauncher:)` / `DebugOverlay(showLauncher:)` is ignored once you pass
> a `controller` — the controller owns that flag, so it can be flipped while running. Set the
> initial value on the controller instead, as above.

### Presentation

```dart
DebugOverlay(
  presentation: DebugOverlayPresentation.bottomSheet,  // dialog | fullscreen | bottomSheet | custom
  ...
)
```

The panel is drawn as a layer inside the overlay's own `Stack` — it is **not pushed onto your
Navigator**. Opening the tools therefore never touches your route stack, and back/pop behaviour
in your app is unaffected. It also means `DebugOverlay` works correctly above `MaterialApp`,
where no `Navigator` or `Localizations` exists yet.

`custom` presents nothing — you render `DebugToolsScreen` yourself (a side panel, an inline
tab, wherever) and use the controller purely as an on/off signal:

```dart
ValueListenableBuilder<bool>(
  valueListenable: debug.isOpenListenable,
  builder: (_, isOpen, __) => isOpen
      ? DebugToolsScreen(pages: pages, onClose: debug.close)
      : const SizedBox.shrink(),
)
```

### Enabling

`runDebugApp(enabled: false)` renders nothing, captures nothing, and intercepts nothing. Wire
it to whatever gate you want:

```dart
enabled: kDebugMode,                                   // debug builds only
enabled: kDebugMode || const bool.fromEnvironment('DEV_TOOLS'),
enabled: user.isInternal,                              // a runtime flag
```

**It also drives the kill switch**, so the UI and the capture can't drift apart — see below.

### The kill switch — release safety

The adapters are installed by **you**, not by the overlay:

```dart
final dio = Dio()..interceptors.add(DebugDioInterceptor());   // ← always on
```

So hiding the UI isn't enough. Without a global switch, a release build with that interceptor
still in place would keep buffering **500 requests — headers, auth tokens, response bodies —
in memory**, with nothing to read it and no reason to exist.

`DebugOverlayKillSwitch` closes that. It defaults to `kDebugMode`, so **a release build
captures nothing out of the box** and you don't have to remember anything. When it's off:

- `NetworkLogStore` and `LogStore` (which also holds errors) become no-ops.
- Mock rules never intercept (it beats an active rule *and* offline mode).
- Turning it off **clears** whatever was already captured.
- The interceptor stays a passthrough, so **disabling the tools can't break your networking**.

`runDebugApp(enabled:)` sets it for you. Set it directly if you don't use `runDebugApp`, or
want it on in a staging release:

```dart
DebugOverlayKillSwitch.enabled = kDebugMode || const bool.fromEnvironment('DEV_TOOLS');

// …or flip it at runtime — tools behind a login in a support build:
DebugOverlayKillSwitch.enabled = user.isInternal;
```

### Launcher appearance

```dart
DebugOverlay(
  launcherCorner: DebugLauncherCorner.bottomLeft,
  launcherMargin: const EdgeInsets.all(24),
  launcherSize: 56,
  launcherIcon: Icons.terminal,
  launcherBuilder: MyOwnButton(),   // replace the visuals entirely; still draggable
  ...
)
```

### Theming

```dart
DebugOverlay(
  theme: const DebugOverlayTheme.dark(),
  // or override any single color:
  // theme: const DebugOverlayTheme(accent: Color(0xFFAA00FF), background: Colors.black),
  ...
)
```

---

## Example

`example/` is a runnable app: dio + http requests, a forced 404, a custom page, and buttons
that toggle the launcher at runtime.

```bash
cd example && flutter run
```
