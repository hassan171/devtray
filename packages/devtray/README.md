# devtray

An in-app debugging overlay for Flutter: a draggable floating button that opens a tabbed
tools panel over your running app.

Eight built-in pages — **Timeline** (everything on one time axis, with UI-freeze detection),
**Network** (with mocking), **Logs** (errors folded in), **State**, **Storage**, **Visual**,
**Device** and **Export** — and every other tab is one you add.

Install `DevtrayNavObserver` and every log line and request also carries the screen it
happened on.

You decide **whether** it exists, **when** it opens, and **how** it's presented.

<p align="center">
  <img src="https://raw.githubusercontent.com/hassan171/devtray/main/docs/assets/hero.gif"
       alt="Dragging the devtray button open and switching between the Timeline, Network and Logs pages"
       width="320">
</p>

---

## Install

The core has **no dependencies** beyond Flutter itself. Every integration — dio, http,
bloc, `shared_preferences`, device info, HTML preview — is a separate package, so you only
compile the ones you use:

```yaml
dependencies:
  devtray: ^0.6.2          # the overlay, the pages, the stores

  # Add only what you need:
  devtray_dio: ^0.6.2       # DebugDioInterceptor
  devtray_http: ^0.6.2      # DebugHttpClient
  devtray_bloc: ^0.6.2      # DebugBlocObserver     → the State page
  devtray_riverpod: ^0.6.2  # DebugRiverpodObserver → the State page
  devtray_prefs: ^0.6.2     # SharedPreferences adapter + mock persistence
  devtray_hive: ^0.6.2      # browse and edit Hive boxes
  devtray_sqflite: ^0.6.2   # every SQLite table, discovered from the schema
  devtray_device: ^0.6.2    # real device/OS/app facts
  devtray_html: ^0.6.2      # preview HTML response bodies
  devtray_log_file: ^0.6.2  # write logs to rotating files, browse past runs
```

A Riverpod app that uses `package:http` takes `devtray`,
`devtray_http` and `devtray_riverpod` — and never compiles dio or
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
import 'package:devtray/devtray.dart';
import 'package:devtray_dio/devtray_dio.dart';
import 'package:devtray_device/devtray_device.dart';

final dio = Dio()..interceptors.add(DebugDioInterceptor());

void main() => runDebugApp(
  () => const MyApp(),
  pages: const [
    NetworkDebugPage(),
    LogsDebugPage(), // logs + errors in one filterable stream
    DeviceDebugPage(provider: PluginDeviceInfoProvider()),
  ],
);
```

Every request through that `dio` now shows up in the overlay, along with your logs, any
uncaught errors, and the device's specs. Nothing else to wire up.

`runDebugApp` installs the log/error capture *and* wraps your app in the overlay. Capture is
already gated on `kDebugMode` via `Devtray.enabled`, so a release build records nothing; wrap
the call in your own `if` when you want the package gone from the tree entirely.

It takes every option `DevtrayOverlay` does — `presentation`, `theme`, `showLauncher`, the
launcher's corner/size/icon. See
[Controlling when and how it opens](#controlling-when-and-how-it-opens).

### Configuring the stores

Everything the overlay captures is tuned in one place, through `configure:`:

```dart
void main() => runDebugApp(
  () => const MyApp(),
  configure: (devtray) => devtray
    // Keep noisy background traffic out of the request list.
    ..excludeUrls(['/health', '/metrics'])
    // Ambient values carried by every log line AND network request.
    ..context({'build': '1.4.2+318', 'flavor': 'staging'})
    // Computed per entry, for values that must be current.
    ..enrich('connectivity', () => {'online': connectivity.isOnline})
    // Fields a source holds outside its state.
    ..inspect<CartCubit>((c) => {'items': c.items.length})
    // Watch for UI freezes for the whole session.
    ..detectFreezes()
    // A line per navigation, on top of the `screen` field the observer sets.
    ..navigation(logNavigation: true),
  pages: const [...],
);
```

**Why a callback and not more arguments.** `configure` runs at the one moment when
everything is ready: after the kill switch is set, after the capture hooks are installed,
and before your `setup` bootstrap. Configuring a store *before* the kill switch silently
does nothing — a store that has been told it's disabled quietly refuses writes — and that
was easy to hit when setup was spread across the singletons.

It is also **skipped entirely** when `enabled` is false, so anything expensive inside it —
an enricher that reads the filesystem, a sink that opens a socket — costs a release build
nothing.

| Method | Configures |
|---|---|
| `excludeUrls`, `network(...)` | Which requests are recorded, how much of each body, and which headers the pane shows |
| `disableMocking`, `persistMockRules` | Request mocking |
| `logs(...)`, `context`, `enrich` | The log buffer and what every entry carries |
| `logTo`, `logToAsync` | Where logs go when they leave memory |
| `inspect<T>`, `inspectAll`, `formatState<T>`, `formatSource<S>`, `state(...)` | The State page |
| `detectFreezes(...)` | UI-freeze and slow-frame detection |
| `capture(...)`, `launcher(...)`, `openOnStart()` | Whether it records, whether it's visible, whether it opens at launch |
| `onLog`, `onError`, `onRequest`, `onResponse`, `onFailure`, `onScreen`, … | Callbacks on what's captured — see [Listening to what's captured](#listening-to-whats-captured) |
| `raw(() { ... })` | Anything not covered — reach straight for the stores |

Registering several inspectors reads better as a list:

```dart
..inspectAll([
  Inspect<CartCubit>((c) => {'items': c.items.length}),
  Inspect<Session>((s) => {'signIns': s.signIns}),
])
```

Each entry is an `Inspect<T>` rather than a bare callback because the registry is keyed by
the source **type** — a list of plain functions would erase it, and your callback would
receive an `Object` to cast. `inspect<T>` remains exactly right for a single one.

Sinks that must be opened asynchronously — the file case — use `logToAsync`, which
`runDebugApp` awaits before running your app, so lines logged during bootstrap still reach
the sink:

```dart
..logToAsync(() => FileLogSink.open())
```

### Redacting headers

A captured `authorization` header carries a live token, and the tools make that token easy
to copy — into a cURL command, a JSON export, a bug report a user pastes into a ticket.
`hideHeaders` masks a header's value everywhere it would otherwise leave the device:

```dart
..network(hideHeaders: {'authorization', 'cookie', 'x-api-key'})
```

The **name is kept, the value becomes `••••••`** — in the detail pane, in copy-as-cURL, in
`toJson`, in every `NetworkSink`, and in `DebugReport`. So a reader sees that an
`authorization` header *was* sent without seeing what it was, and the request still shows
its shape.

For a family that doesn't enumerate, `hideHeader` takes a predicate — both apply, so the
set can cover the common names while the callback catches the rest:

```dart
..network(hideHeader: (name) => name.startsWith('x-internal-'))
```

Or hide **every** header at once — a screenshot or report that should carry none:

```dart
..network(hideAllHeaders: true)
```

**Mask or omit.** By default a hidden header is *masked* — name kept, value `••••••`. Pass
`headerHiding: HeaderHiding.omit` to drop it entirely instead, as if it were never on the
request — for decluttering, or when even a header's presence is more than you want to reveal:

```dart
..network(hideHeaders: {'authorization'}, headerHiding: HeaderHiding.omit)
```

Names match **case-insensitively**, since HTTP header names are case-insensitive and a Dart
`Set` isn't — `Authorization` and `authorization` are the same header either way.

Two things this is **not**. It masks on the way *out*, so the value is still held in memory
on the live entry — if you need it never *recorded*, strip it in your own adapter before it
reaches `DevtrayNet.add`. And it's for secrets, not noise: masking a chatty `user-agent`
still leaves a `user-agent: ••••••` line in the pane, so it doesn't declutter — it hides.

### Listening to what's captured

Everything above configures what devtray **records**. The `on…` methods hand each recorded
item back, so your app can act on it:

```dart
configure: (devtray) => devtray
  ..onError((e) => Sentry.captureException(e.error ?? e.message, stackTrace: e.stackTrace))
  ..onResponse((r) {
    if (r.statusCode == 401) authBloc.add(SessionExpired());
  })
  ..onScreen((v) => analytics.screenView(v.name))
  ..onFreeze((f) => analytics.track('ui_freeze', {'ms': f.duration.inMilliseconds})),
```

This is what the `tick` notifiers on each store can't do. Those are a "something changed,
rebuild" signal for the pages: coalesced, so a burst of ten requests fires once, and carrying
no payload — finding out *what* arrived means diffing the buffer yourself.

| Method | Fires |
|---|---|
| `onLog` / `onError` | Every log line / only the errors |
| `onRequest` / `onResponse` / `onFailure` | A request starts / completes / failed |
| `onScreen` / `onScreenLeave` | A route is entered / left (with `duration` filled in) |
| `onStateChange` / `onStateError` | A tracked source emitted / reported an error |
| `onFreeze` / `onSlowFrame` | A UI freeze ended / a frame ran long |

`onError` is the crash-reporter hook, and it covers every route into the log store at once:
your own `Devtray.report` calls, the Flutter and platform error handlers `runDebugApp`
installs, and failed requests forwarded from the network store. One registration sees them
all.

**Observe-only.** Listeners run *after* the item is recorded and cannot change or suppress
it. A listener that throws is caught, reported as an error line naming which list it was on,
and the remaining listeners still run — one broken callback is a bug in that callback, not a
reason to lose the entry it was watching or to take down the app being debugged.

Nothing fires while `Devtray.enabled` is false, because nothing is recorded.

#### Listeners scoped to a widget

Registrations made in `configure` last the whole session. For one tied to a widget, call the
store's own method — it returns a disposer:

```dart
class _CheckoutState extends State<Checkout> {
  late final DevtrayUnsubscribe _off;

  @override
  void initState() {
    super.initState();
    _off = DevtrayNet.instance.onFailure(_showRetryBanner);
  }

  @override
  void dispose() {
    _off();
    super.dispose();
  }
}
```

A returned disposer rather than a `removeListener(fn)` pair because the registration is
usually a closure written inline, and removing it later would otherwise mean hoisting it to a
field purely so there's something to pass back.

#### Removing them all at once

For the blunt case — a sign-out that should undo whatever the signed-in session registered,
or a test between cases:

```dart
Devtray.clearListeners();       // every store

Devtray.clearLogListeners();    // onLog, onError
Devtray.clearNetworkListeners();// onRequest, onResponse, onFailure
Devtray.clearNavListeners();    // onScreen, onScreenLeave
Devtray.clearStateListeners();  // onStateChange, onStateError
Devtray.clearJankListeners();   // onFreeze, onSlowFrame
```

These are blunt on purpose: they drop listeners *anything* registered, including a package's.
When you only mean to undo your own, hold the disposer.

None of them are the same as `Devtray.enabled = false`. Switching capture off already stops
every listener firing, because nothing is recorded; these drop the registrations themselves,
so they don't come back when capture is switched on again.

#### One caveat: `onSlowFrame`

`onSlowFrame` is the only listener that runs **inside the frame pipeline**, and on a bad
scroll it can fire every frame. Keep it to a counter, and don't touch widget state from it —
marking something dirty there is a build during a build. Prefer `onFreeze` for anything
heavier; a slow-frame listener doing real work becomes the jank it's measuring.

### Logging from your app

Use the `Devtray` statics at call sites. They're no-ops when the overlay is disabled, so
they're safe to leave in code that ships:

```dart
Devtray.log('User signed in', level: LogLevel.info, tag: 'auth');
Devtray.report(error, stackTrace: stack);
Devtray.setContext('userId', user.id);        // ambient, from here on
await Devtray.withContext({'orderId': id}, () async => submitOrder());
```

The stores are still public for everything else — reading `DevtrayJank.instance.freezes`,
feeding `DevtrayNet.instance` from a hand-rolled adapter. `Devtray` is the shorthand for
the common path, not a wall around the rest.

### Already have a bootstrap?

`runDebugApp` takes a `setup` callback, run **inside** the capture Zone and awaited before the
first frame — so your Firebase init, your dotenv load, and anything they log or throw are all
captured:

```dart
void main() => runDebugApp(
  () => const MyApp(),
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

    runApp(DevtrayOverlay(pages: const [...], child: const MyApp()));
  },
  (error, stack) => DevtrayLog.instance.report(error, stackTrace: stack, source: ErrorSource.uncaught),
  zoneSpecification: ZoneSpecification(
    print: (self, parent, zone, line) {          // bare print()
      DevtrayLog.instance.log(line);
      parent.print(zone, line);
    },
  ),
);
```

They're separate because the Zone has to be installed *around* `runApp`, and `Devtray` is
a widget that only exists inside it — a widget can't wrap its own `runApp` call.

If you can't own `runApp` at all, call `captureErrors()` and `captureDebugPrint()` anywhere
during startup. You'll still get `debugPrint` and framework errors; you'll miss bare `print()`
and uncaught async errors, which genuinely require the Zone.

---

## Timeline

Every other page answers *"what happened to **this**"*. `TimelineDebugPage` answers **"what
just happened"** — requests, logs, state changes and UI freezes on one shared time axis.

```dart
pages: [TimelineDebugPage()],
```

That's the whole setup. **It owns no data.** Every store already timestamps its entries, so
this is a *view* over the three existing stores rather than a fourth to keep in sync — and it
costs nothing until you open it.

```
        14:32:01        :02        :03        :04        :05
JANK                              ███████ 900ms
NET     ▬▬▬▬▬▬ GET /items    ▬▬ POST /cart   ▬▬▬▬▬▬▬▬▬▬ GET /photos
LOG     · ·  ··    ·        ▲              · ·   ▲▲
STATE      ◆ CartCubit          ◆ CartCubit   ◆ SessionNotifier
```

Requests draw as **bars**, because they have duration. Logs and state changes draw as
**marks**, because they're instants. The payoff is the vertical alignment: the 900ms freeze
sitting directly above the request that landed a moment before it.

**Tap anything** for its detail — the same dialog the owning page would show, so nothing
drifts from the real thing.

### Reading it

| Control | What it does |
|---|---|
| **LIVE / PAUSED** | Follows the newest events, or holds still. Any drag pauses it — you can't read a window that's also sliding. |
| **Drag the lanes**, or **‹ ›** | Scroll back through history. The buttons step half a window each. |
| **Zoom slider** | 200ms to 10 minutes, logarithmic. The sub-second end is where you see ordering *inside* a frame's work. |
| **Lane chips** | Mute a lane. Muted lanes are excluded from collection, not just hidden, so they cost nothing. |

Zoom survives the live/paused toggle — pick a scale, pause to read, resume watching *at that
scale*. The **reset** button beside the slider is the explicit way back.

### Detecting UI freezes

Opt-in, because it's the only capture in the overlay with a real steady-state cost:

```dart
pages: [TimelineDebugPage(detectFreezes: true)],
```

That scopes the watchdog to while the page is mounted. To watch the whole session — including
freezes that happen while the overlay is closed, or while you're on another tab — start it
from `configure` instead:

```dart
configure: (devtray) => devtray..detectFreezes(),
```

Two different things land in the jank lane:

- **Freezes** — solid red bars. The UI isolate stopped responding entirely.
- **Slow frames** — amber marks. The frame *rendered*, just late. Tapping one gives you the
  build-vs-raster split: slow build points at widget work, slow raster at painting or shaders.

> **What this can't do.** A frozen isolate cannot detect its own freeze — while it's blocked,
> no timer, frame callback or microtask runs, including this one. So detection is
> **retrospective**: the heartbeat notices on its *next* tick that far more wall-clock time
> passed than it asked for. Three consequences worth knowing:
>
> - A freeze is only reported **once it ends**. A terminal hang is reported by nothing.
> - There is **no stack trace**. By the time the gap is measurable, whatever caused it has
>   returned.
> - `addTimingsCallback` alone isn't enough — it only fires for frames that *rendered*, so a
>   three-second block produces no timings at all. That's why both are used.

Because there's no stack trace, tapping a freeze shows **what else was happening** in that
window — the requests, logs and state changes from the other lanes. That's circumstantial,
and the dialog says so rather than implying a cause it can't prove. It's usually enough:
a 900ms freeze directly after a large response arrived is a strong hint about where to look.

Tune it if the defaults don't fit:

```dart
..detectFreezes(
  threshold: const Duration(milliseconds: 500),          // default 250ms
  slowFrameThreshold: const Duration(milliseconds: 50),  // default 32ms
  heartbeatInterval: const Duration(milliseconds: 50),   // default 100ms
)
```

The threshold has to stay well above ordinary timer jitter — timers routinely run a few
milliseconds late, and a threshold near zero reports constant phantom freezes.

---

---

## Navigation

Every log line and network request can carry the screen it happened on. Install the observer
and there is nothing else to do:

```dart
MaterialApp(
  navigatorObservers: [DevtrayNavObserver()],
  ...
)
```

From then on `screen: /checkout` rides along on everything captured, so *"which screen was I
on when that 500 came back"* is answered on the entry itself rather than reconstructed from
timestamps. Open any request's **Context** tab to see it.

### What it can and cannot see

It sees the **Navigator** — pushed routes, `pushNamed`, and most routers built on one.

It cannot see a custom shell. An `IndexedStack` or a `PageView` whose body swaps on a tab tap
pushes no route, so there is nothing to observe and no observer could ever fire. Only the app
knows a swap happened, so tell devtray at the point that already knows:

```dart
onDestinationSelected: (i) {
  Devtray.screen(_titles[i]);
  setState(() => _tab = i);
}
```

Both feed the same history, so an app with a tab shell *and* pushed routes gets one coherent
picture rather than two half-pictures.

### Unnamed routes

`Navigator.push(MaterialPageRoute(builder: ...))` carries no name, and there is nothing to
read. Such a route reports `<unnamed MaterialPageRoute>` rather than silently keeping the
previous screen — a field that quietly names a page you already left is worse than one that
admits it doesn't know. Fix it by naming the route:

```dart
MaterialPageRoute(
  settings: const RouteSettings(name: 'note_editor'),
  builder: (_) => const NoteEditorScreen(),
)
```

Or derive names yourself:

```dart
DevtrayNavObserver(
  nameOf: (route) => switch (route.settings.arguments) {
    NoteArgs(:final id) => 'note/$id',
    _ => null,                              // null falls back to the default
  },
)
```

### Dialogs and sheets

A dialog over Checkout does **not** change the screen. It adds its own field instead:

```
screen:  "/checkout"      ← the page, untouched
overlay: "DialogRoute"    ← what is on top of it
```

Two fields rather than one because a request fired from behind that dialog came from
*Checkout* — labelling it `DialogRoute` would replace a real page name with a placeholder and
lose the thing you wanted. The overlay field is removed on dismiss, so nothing is left behind
claiming a dialog is up.

Anything that is not a `PageRoute` counts as an overlay.

### The Timeline's `nav` lane

Route changes draw as **spans**, not marks — "which screen was I on at this moment" is an
interval question, and drawing it as one answers it directly instead of making you read
between two ticks. Contiguous spans alternate their shading so the joins are visible.

Each span is labelled with the journey rather than the destination:

```
/ → /settings      pushed
/ ← /settings      popped back
```

Direction matters: `a → b` and `b ← a` involve the same two names but are different journeys,
and a lane showing only the pair could not tell them apart. Returning is recorded as its own
visit, so the trip back is a span in its own right.

Tap any span for its detail — where it came from, how long it lasted, and whether it is still
open.

### Logging each navigation

Off by default. The `screen` field already puts the route on every entry, so a line per
navigation is largely redundant — and a nav-heavy app would spend a chunk of the 1000-entry
buffer on them. Turn it on when you want the route trail as its own filterable thing:

```dart
configure: (d) => d..navigation(logNavigation: true),
```

Lines are tagged `nav`, so the Logs page can filter to just them.

## Network

The overlay reads from a single transport-agnostic sink, `DevtrayNet`. Three ways in:

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
final entry = DevtrayNet.instance.add(
  method: 'GET',
  uri: uri,
  requestHeaders: headers,
  requestBody: body,
);

// ...later, when the response lands (entry is null if the URL was excluded):
DevtrayNet.instance.complete(
  entry!.id,
  status: NetworkLogStatus.success,
  statusCode: 200,
  responseHeaders: {'content-type': ['application/json']},
  responseBody: json,
);
```

Keep noisy background traffic out of the list:

```dart
DevtrayNet.instance
  ..excludedUrlPatterns.addAll(['/health', '/log-error'])
  ..maxEntries = 300;   // default 500, oldest dropped first
```

Attach transport-specific context as its own detail tab:

```dart
DevtrayNet.instance.attachExtra(entry.id, 'Proxy JS', generatedJs);
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
  devtray_html: ^0.6.2
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
entirely, call `DevtrayMocks.instance.disable()` — that stops the interception *and* takes the
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
DevtrayMocks.instance.offline.value = true;               // kill the network

DevtrayMocks.instance.add(MockRule(
  id: DevtrayMocks.instance.nextId(),
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
  devtray_prefs: ^0.6.2
```

```dart
DevtrayMocks.instance.storage = SharedPreferencesMockRuleStorage();
```

That's the whole opt-in — setting a backend *is* the switch, so there's no flag to keep in
sync with it. It's opt-in at all because persistence means a real storage package, and the
core doesn't depend on `shared_preferences` — no app should carry that for a debug tool it may
not use.

Only the rules are stored (a small JSON blob); no logs, no request bodies, so none of the PII
concerns that make persisting the *data* a bad idea. Swap the backend by implementing
`MockRuleStorage` and setting `DevtrayMocks.instance.storage` — that's the same seam
`devtray_prefs` uses.

### Don't want mocking at all?

One line, and it's the real one:

```dart
DevtrayMocks.instance.disable();
```

That stops the adapters intercepting — it beats offline mode, every rule, and skips restoring
persisted rules on the next launch. The Network page reads it too, so the Mocks button, "Mock
this request" and the interception warning all disappear with it.

There's deliberately no separate flag for the UI. There used to be, and it was a trap: hiding
the affordances while the adapters went on consulting `DevtrayMocks` meant a rule added **from
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

### Context on every entry

Three layers, composing least-specific to most. All of them land on **log lines and network
requests alike**, so one registration labels both.

```dart
// 1. ambient — set once, carried until changed
Devtray.setContext('userId', user.id);

// 2. enrichers — computed per entry, for values that must be current
configure: (d) => d..enrich('nav', () => {'screen': router.currentRoute}),

// 3. per-call — one entry only
Devtray.log('Checkout failed', fields: {'cartId': cart.id});
```

Later wins over earlier, which is the useful order: the more specific the source, the more it
knows. A call-site field beats an enricher, which beats ambient context.

`withContext` scopes values to a span of work and restores what was there:

```dart
await Devtray.withContext({'orderId': id}, () async => submitOrder());
```

Not safe across concurrent async work — it is one shared map, not Zone state, so overlapping
scopes on the same key interleave. Pass the field explicitly when you need per-request
isolation.

**On requests**, these appear on the detail pane's **Context** tab — deliberately not next to
Request Headers and Request Body, where they read as something the app *sent*. They are the
opposite: state recorded on the device at the moment of the call, transmitted nowhere.

**Cost when unused is nothing.** With no context, no enrichers and no per-call fields, the
resolver returns a shared const map without allocating. With only ambient context it hands
back a shared snapshot, so context set once is free per entry however many entries there are.

Enrichers run on **every** capture, so keep them cheap — a field read, not a platform channel
call. One that throws has its failure recorded as the field's value (visible on the entry it
broke, rather than silently missing), and after repeated failures it is dropped and a line
logged saying so. A broken enricher never costs you the entry it was decorating.

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
import 'package:devtray/devtray.dart';

log('user signed in', name: 'auth', level: 800);   // DevTools *and* the Logs page
```

`name` becomes the entry's tag, `level` maps onto `LogLevel` via the `package:logging` scale
(FINE 500 / INFO 800 / WARNING 900 / SEVERE 1000) that `developer.log` documents. The real
`developer.log` is still called, so DevTools is unaffected. If `log` collides with something in
scope (`dart:math` exports one too), use `debugLog` — same function, unambiguous name.

### Hooking in your own logger

If you already use `logger`, `talker`, `logging`, or something homegrown, keep it. The page
reads from `DevtrayLog` and nothing else, so bridging is one call:

```dart
Devtray.log(
  'User signed in',
  level: LogLevel.info,
  tag: 'auth',
  error: someError,       // optional
  stackTrace: someStack,  // optional
);
```

(`Devtray.log` is shorthand for `DevtrayLog.instance.log` — either works. The examples below
use the store directly where the surrounding code already holds a reference to it.)

Use `debugLevelFromName('SEVERE')` / `debugLevelFromSeverity(1000)` to map a foreign level
onto `LogLevel` — they understand the aliases the common packages use (`severe`, `wtf`,
`warn`, `finest`, …).

**package:logger** — add an output alongside your console one, and your existing setup is
untouched:

```dart
class DevtrayLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) => DevtrayLog.instance.log(
    event.lines.join('\n'),
    level: debugLevelFromName(event.level.name),
  );
}

final logger = Logger(output: MultiOutput([ConsoleOutput(), DevtrayLogOutput()]));
```

**package:logging**

```dart
Logger.root.onRecord.listen((r) => DevtrayLog.instance.log(
  r.message,
  tag: r.loggerName,
  level: debugLevelFromName(r.level.name),
  error: r.error,
  stackTrace: r.stackTrace,
));
```

**talker**

```dart
talker.stream.listen((d) => DevtrayLog.instance.log(
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
DevtrayOverlay(showErrorBadge: false, ...)   // if you'd rather it didn't
```

Report your own caught errors — they show up as error rows just the same:

```dart
try {
  await risky();
} catch (e, s) {
  DevtrayLog.instance.report(e, stackTrace: s);
  rethrow;
}
```

There is **one store**: `DevtrayLog` holds ordinary logs and errors alike. An error is just an
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
`DevtrayNet.instance.errorReporting.value = ...`.

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
DevtrayOverlay(
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
`DevtrayTheme.of(context)` for colors.

---

## Controlling when and how it opens

Three separate questions, deliberately not one switch — a staging build reasonably wants
capture running with no visible affordance:

| | Question | Where |
|---|---|---|
| **Capture** | is it recording? | `Devtray.enabled` |
| **Visibility** | can it be seen or opened? | `Devtray.open()`, `Devtray.showLauncher` |
| **Existence** | is it in the tree at all? | your own `if` around `runDebugApp` |

### Open it from anywhere

```dart
Devtray.open();
Devtray.close();
Devtray.toggle();
```

No controller to construct, inject or thread through your app — a process has one panel, so
`Devtray` holds it. Call these from a shake detector, a 5-tap on the logo, a hidden settings
row, a test.

### Hide the floating button and use your own

The draggable button is on by default, but it's just *a* way in — not the only one:

```dart
runDebugApp(
  () => const MyApp(),
  configure: (d) => d..launcher(false),   // no visible affordance
  pages: [...],
);

// …then anywhere in your app:
IconButton(onPressed: Devtray.open, icon: const Icon(Icons.bug_report))
```

Toggle it while running:

```dart
Devtray.showLauncher = false;   // hide
Devtray.showLauncher = true;    // show
```

That's how you ship a build with **no visible debug affordance** but a secret way in.

`runDebugApp(showLauncher:)` and `DevtrayOverlay(showLauncher:)` set the same thing, as a
default. Setting it on purpose — via `configure` or by assigning `Devtray.showLauncher` —
always wins, whenever the overlay happens to mount.

### Presentation

```dart
DevtrayOverlay(
  presentation: DevtrayPresentation.bottomSheet,  // dialog | fullscreen | bottomSheet | custom
  ...
)
```

The panel is drawn as a layer inside the overlay's own `Stack` — it is **not pushed onto your
Navigator**. Opening the tools therefore never touches your route stack, and back/pop behaviour
in your app is unaffected. It also means the overlay works correctly above `MaterialApp`,
where no `Navigator` or `Localizations` exists yet.

`custom` presents nothing — you render `DebugToolsScreen` yourself (a side panel, an inline
tab, wherever) and use the open state purely as a signal:

```dart
ValueListenableBuilder<bool>(
  valueListenable: Devtray.isOpenListenable,
  builder: (_, isOpen, __) => isOpen
      ? DebugToolsScreen(pages: pages, onClose: Devtray.close)
      : const SizedBox.shrink(),
)
```

### Keeping it out of a release build

There is no `enabled` flag on `runDebugApp`, on purpose. That call installs a capture Zone and
replaces `debugPrint` and `FlutterError.onError` — all before any flag could be read — so a
flag could only ever turn off *part* of it while leaving the hooks in place. A switch that
silently does half its job is worse than none.

Decide outside, where the decision is total:

```dart
void main() {
  if (kDebugMode) {
    runDebugApp(() => const MyApp(), pages: [...]);
  } else {
    runApp(const MyApp());
  }
}
```

### The capture switch — release safety

The adapters are installed by **you**, not by the overlay:

```dart
final dio = Dio()..interceptors.add(DebugDioInterceptor());   // ← always on
```

So hiding the UI isn't enough. Without a global switch, a release build with that interceptor
still in place would keep buffering **500 requests — headers, auth tokens, response bodies —
in memory**, with nothing to read it and no reason to exist.

`Devtray.enabled` closes that. It defaults to `kDebugMode`, so **a release build captures
nothing out of the box** and you don't have to remember anything. When it's off:

- `DevtrayNet` and `DevtrayLog` (which also holds errors) become no-ops.
- Mock rules never intercept (it beats an active rule *and* offline mode).
- `DevtrayJank` stops its heartbeat — the one steady-state cost in the package.
- Turning it off **clears** whatever was already captured.
- The interceptor stays a passthrough, so **disabling the tools can't break your networking**.

Set it for a staging release, or flip it at runtime:

```dart
Devtray.enabled = kDebugMode || const bool.fromEnvironment('DEV_TOOLS');

// …tools behind a login in a support build:
Devtray.enabled = user.isInternal;
```

Decided at startup, say it in `configure` alongside everything else — `..capture(...)` is the
same switch:

```dart
configure: (d) => d
  ..capture(true)          // record in every build…
  ..launcher(kDebugMode),  // …but no visible affordance outside debug
```

That pairing is why capture and visibility are separate switches. A build that ships the tray
on purpose — QA pulling network logs off TestFlight, with the launcher gated to a few accounts
— wants recording running for **everyone**, so the tray holds a full session the moment it's
opened rather than starting empty from the point someone signed in.

Settings from `configure` are applied regardless, so enabling capture mid-session finds your
excluded URLs and enrichers already registered.

### Launcher appearance

```dart
DevtrayOverlay(
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
DevtrayOverlay(
  theme: const DevtrayTheme.dark(),
  // or override any single color:
  // theme: const DevtrayTheme(accent: Color(0xFFAA00FF), background: Colors.black),
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
