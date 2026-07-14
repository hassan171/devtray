# debug_overlay

An in-app debugging overlay for Flutter: a draggable floating button that opens a tabbed
tools panel over your running app.

Four built-in pages — **Network**, **Logs**, **Errors**, **Device** — and every other tab is
one you add.

You decide **whether** it exists, **when** it opens, and **how** it's presented.

---

## Install

```yaml
dependencies:
  debug_overlay:
    path: ../debug_overlay   # or a git ref
```

## Quick start

Swap `runApp` for `runDebugApp` and list the pages you want. That's the whole setup:

```dart
import 'package:debug_overlay/debug_overlay.dart';

final dio = Dio()..interceptors.add(DebugDioInterceptor());

void main() => runDebugApp(
  const MyApp(),
  enabled: kDebugMode,
  pages: const [
    NetworkDebugPage(),
    LogsDebugPage(),
    ErrorsDebugPage(),
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

### If you can't hand over `runApp`

Add-to-app, a custom bootstrap, or a test may not let you. Then do it by hand — this is what
`runDebugApp` expands to:

```dart
void main() => DebugOverlayCapture.runApp(          // the capture Zone
  () => runApp(
    DebugOverlay(pages: const [...], child: const MyApp()),   // the UI
  ),
);
```

They're separate because the Zone has to be installed *around* `runApp`, and `DebugOverlay`
is a widget that only exists inside it — a widget can't wrap its own `runApp` call.

If you can't own `runApp` at all, call `DebugOverlayCapture.installHooks()` anywhere during
startup instead. You'll still capture `debugPrint` and framework errors; you'll miss bare
`print()` and uncaught async errors, which genuinely require the Zone.

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
(pretty-printed JSON), query params, error message, **copy-as-cURL**, and an **HTML preview**
for HTML responses. Multipart bodies are snapshotted and rendered as `-F` flags in the cURL.

---

## Logs

`LogsDebugPage` shows captured log output, filterable by level and tag, searchable, with the
whole filtered view copyable as plain text for a bug report.

**What gets captured depends on how you start the app:**

| | `debugPrint` | framework errors | bare `print()` | uncaught async errors |
|---|---|---|---|---|
| `runDebugApp(...)` / `DebugOverlayCapture.runApp(...)` | ✅ | ✅ | ✅ | ✅ |
| `DebugOverlayCapture.installHooks()` | ✅ | ✅ | ❌ | ❌ |

Bare `print()` and uncaught async errors can only be intercepted from inside a custom `Zone`,
which means owning the `runApp` call. If you'd rather not, call `installHooks()` anywhere
during startup and accept the two gaps. Nothing is ever swallowed — logs still print and
errors still reach the console and the red error screen.

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

`ErrorsDebugPage` collects uncaught exceptions and framework errors, with the full stack
trace, the widget-ownership context, and a one-tap "copy report".

The point is the errors **nobody was watching the console for** — so the launcher grows a red
count badge when errors arrive, and opening the page clears it:

```dart
DebugOverlay(showErrorBadge: false, ...)   // if you'd rather it didn't
```

Report your own caught errors into it:

```dart
try {
  await risky();
} catch (e, s) {
  ErrorStore.instance.report(e, stackTrace: s);
  rethrow;
}
```

### Failed requests land here too

A failed request is an error, so the Network page forwards failures to the Errors page —
which means a dead backend badges the launcher instead of waiting for you to think to open
the Network tab. The Errors detail shows the request, response headers and response body
(a transport failure has no meaningful Dart stack, so the request itself is the diagnostic).

**Not every failure, though.** A 404 on a "does this exist?" probe and a 401 that kicks off a
token refresh are routine — badging on those trains you to ignore the badge. So the default
forwards **5xx and transport failures** (timeout, refused connection, bad certificate) and
leaves 4xx to the Network page.

Change it at any time — it's live, and there's a **bell menu on the Network page** to flip it
mid-session without touching code:

```dart
NetworkLogStore.instance.errorReporting.value = NetworkErrorReporting.all;   // include 4xx
NetworkLogStore.instance.errorReporting.value = NetworkErrorReporting.none;  // stop forwarding
```

| Mode | Forwards |
|---|---|
| `none` | nothing — failures stay on the Network page |
| `serverAndTransport` *(default)* | 5xx + transport failures |
| `all` | every failed request, 4xx included |

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
`CopyableSection`, `CopyButton`, `DebugTabBar`, `HtmlPreviewDialog`, and
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

`enabled: false` renders nothing and captures no gestures — the overlay is fully inert.
Wire it to whatever gate you want:

```dart
enabled: kDebugMode,                                   // debug builds only
enabled: kDebugMode || const bool.fromEnvironment('DEV_TOOLS'),
enabled: user.isInternal,                              // a runtime flag
```

Note that `enabled` only controls the **UI**. The adapters keep recording into
`NetworkLogStore` regardless — don't install them in a release build if you don't want that.

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
