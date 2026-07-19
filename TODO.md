# devtray — roadmap

Candidate features, with enough design detail to argue about. Each one lists what it does,
how it'd be built, what it costs, and the **open questions** that need a decision before
writing code.

Ordered by value-per-effort. Nothing here is committed.

**Shipped so far:** **Timeline** (with **jank/freeze detection**), Network, **Mocks**,
**Visual**, Logs, Errors, Device, **Export**, **Storage** pages · **kill switch** · pluggable
`DebugPage` system · `runDebugApp` one-call setup · dio + http adapters · network→errors
forwarding · **log persistence** (sinks, rotating session files, a browser for past runs) ·
**structured log context** (ambient / enricher / per-call).

**Explicitly not doing:**
- ~~**Persistence across restarts**~~ — **reversed, and shipped.** The reasoning was that the
  crash-forensics case wasn't worth the machinery. It was: `LogSink`/`DevtrayExport` plus
  `devtray_log_file` write rotating session files, and the Logs page browses past runs. What
  made it worth building was that the machinery turned out to be small — the core defines the
  interface and owns the batching, and the one dependency lives in its own package.
- **Redaction.** Built, then removed — see §3. This is a personal tool; the data is yours and
  goes to your own terminal. A scrubbed cURL can't be replayed, which is the point of copying
  one.

---

## 1. ~~Network mocking~~ ✅ SHIPPED

Built as designed. Decisions taken: rules **persist** (`shared_preferences`, rules-only);
matching is **substring with an opt-in regex toggle**; the body editor is **seeded from the
captured response** ("Mock this request" on any logged request). Mocked traffic is badged
`MOCKED` in the list, warned about in a banner on both pages, and marked in the detail.

Three real bugs surfaced while building it, all caught by tests:
- `onResponse` hardcoded `NetworkLogStatus.success` — a **real** 500 under
  `validateStatus: (_) => true` was logged as a green row. Pre-existing, unrelated to mocking.
- dio's `handler.resolve()` skips the interceptor's own `onResponse`, so mocked requests sat
  **pending** in the log forever. The adapters now complete the entry by hand.
- The editor's "Add rule" button never enabled — it read `controller.text` at build time with
  no listener, so typing a URL didn't rebuild it.

Opting out is a **two-level** switch, because hiding the UI doesn't stop the adapters:
`NetworkDebugPage(enableMocking: false)` drops the button + banner, and
`DevtrayMocks.instance.disable()` stops interception for real (beats offline mode, every rule,
and skips restoring persisted rules).

Still open, if it ever bites:
- **Replay / edit-and-resend** a captured request wasn't built. Mocking covers most of what it
  was wanted for.
- Mocks still aren't gated by `enabled`/`kDebugMode` automatically — a rule left on in a
  staging build would be confusing, and only the banner reveals it. `disable()` is the manual
  answer; an automatic one may be worth it.

<details>
<summary>Original design notes</summary>

### 1. Network mocking ⭐ the big one

Turn the network tab from an **observer** into a **test harness**. Everything else on this
list makes debugging easier; this one lets you reach app states you otherwise **cannot reach
at all** without a backend change.

### What it does
- **Force a response** — canned JSON, a 500, a 401, an empty list. Test error and empty
  states without touching the server.
- **Inject latency** — see your loading spinners; surface race conditions.
- **Simulate offline** — fail everything. (Today: turn off your wifi.)
- **Replay / edit-and-resend** — tap a captured request, tweak the body, fire it again.

### Design sketch
A rule list on `DevtrayNet`, applied by the adapters — the same shape as the
`errorReporting` toggle we already shipped, so it inherits the live-toggle pattern.

```dart
class MockRule {
  final String urlPattern;        // substring or regex
  final String? method;           // null = any
  final Duration? delay;
  final MockResponse? response;   // null = pass through, just delayed
  bool enabled;
}

class MockResponse {
  final int statusCode;
  final dynamic body;
  final Map<String, String> headers;
  final Object? error;            // throw instead of responding (offline sim)
}

DevtrayNet.instance.mockRules.value = [...];
```

`DebugDioInterceptor.onRequest` checks the rules; on a match it either delays, or
short-circuits with `handler.resolve(...)` / `handler.reject(...)`. `DebugHttpClient.send`
does the same before delegating to the inner client.

UI: a "Mocks" section on the Network page — add a rule from a captured request (prefills the
URL and method), toggle rules on/off live, plus a global "offline" master switch.

Mocked responses should be **visibly marked** in the request list (a badge), or you'll waste
an afternoon debugging a response you faked yourself. This is the single most important
detail in the whole feature.

### Cost
Medium. The interception is straightforward in both adapters. The rule-editor UI is the bulk
of it — editing a JSON body on a phone is genuinely awkward.

### Open questions
- **Rule matching:** substring, glob, or full regex? Regex is powerful but painful to type on
  a phone. Lean: substring by default, regex opt-in via a toggle.
- **Body editing UX:** a raw multi-line text field with JSON validation is the honest answer,
  but it's rough on mobile. Alternative: seed the editor from the *actual* captured response
  so you're editing, not authoring from scratch. Much better ergonomics.
- **Do rules survive a hot restart?** They're in-memory like everything else, so no — you'd
  re-add them each session. Painful if you're iterating. This is the one place persistence
  might genuinely earn its keep (a small rules-only JSON file). Worth reconsidering?
- **Should mocking be gated separately from the overlay?** A mock rule left on in a staging
  build would be very confusing. Maybe mocks are `kDebugMode`-only regardless of `enabled`.

</details>

---

## 2. ~~Visual debug toggles~~ ✅ SHIPPED (flags only)

Built the **flags** half: paint layout bounds, repaint rainbow, baselines, tap highlighting,
slow animations. Plus a warning banner + "Reset all", because these are process-wide globals
that outlive the overlay — a rainbow left on looks like a rendering bug. The flag list is
replaceable (`VisualDebugPage(flags: [...])`).

**Layer borders was cut.** `debugPaintLayerBordersEnabled` is drawn in
`PaintingContext.stopRecordingIfNeeded` — only when a layer records a *new* picture, not on
every repaint like the others. Layers with a cached picture never re-record, so the borders
never appear; neither a full `markNeedsPaint()` walk nor `reassembleApplication()` reliably
forces it from inside the app (DevTools drives the engine directly). A switch that silently
does nothing is worse than no switch. Use DevTools for that one.

The **overrides** half (text scale, locale, forced brightness) was deliberately *not* built —
it needs `Devtray` to inject a `MediaQuery`/`Localizations` above the host app's tree,
which is a structural change to a widget that currently touches nothing about the app it
wraps. Still open; see the original notes below.

Notes from building it:
- `reassembleApplication()` is the wrong way to apply a flag — it rebuilds the whole tree
  (the hot-reload path) and re-enters `runApp`, which trips a scheduler assertion under
  `flutter_test`. Walking the render tree with `markNeedsPaint()` is what these flags need.
- **Widget-testing this page is largely not possible.** `flutter_test` runs
  `debugAssertAllRenderVarsUnset` after every test, and the page's whole job is to leave a
  rendering global set. A test that taps a switch poisons every test after it in the file, no
  matter what order you reset/unmount in. Worked around by asserting the flag wiring in a
  plain (non-widget) `test`, and the banner/reset behaviour via a *custom* flag backed by a
  local bool. The real-global paths are verified by hand in the example app.

<details>
<summary>Original design notes</summary>

### 2. Visual debug toggles — best value-per-hour

A page of switches wrapping the flags you'd otherwise need a tethered DevTools session for.
Each is a one-liner; together they cover most on-device visual debugging.

### What it does
- `debugPaintSizeEnabled` — layout boxes
- `debugRepaintRainbowEnabled` — what's repainting
- `debugPaintBaselinesEnabled`, `debugPaintPointersEnabled`
- `showPerformanceOverlay` (needs a hook into the host `MaterialApp` — see below)
- **Text scale override** — a slider. Catches the "breaks at 200% text" bug that ships to
  users constantly.
- **Locale override** — a dropdown. Instantly check RTL / long-German-word layouts.
- **Theme brightness override** — force light/dark.

### Design sketch
The debug flags are globals: set them, then `WidgetsBinding.instance.reassembleApplication()`
to force a repaint. Trivial.

The **overrides** (text scale, locale, brightness) are harder: they need to wrap the host
app's tree, which means `Devtray` would have to inject a `MediaQuery`/`Localizations`
above `widget.child`. That's a real change to the overlay's structure — currently it deliberately
touches nothing about the app it wraps.

### Cost
Low for the flags. **Medium for the overrides**, and they carry a design risk: injecting a
`MediaQuery` above the host app could interact badly with an app that sets its own.

### Open questions
- Are the overrides worth the structural change, or ship just the flags (cheap, zero risk)
  and stop there? **My lean: flags first, overrides only if you'd actually use them.**
- `showPerformanceOverlay` is a `MaterialApp` property, not a global — we can't set it from
  outside. Either skip it, or have `runDebugApp` optionally wrap/patch the app. Skipping is
  fine; the Performance page below is better anyway.

</details>

---

## 3. ~~Share / export bundle~~ ✅ SHIPPED (no redaction)

**`ExportDebugPage` / `DebugReport`** — bundles device + errors + network + logs into one
plain-text report, with section toggles and a full preview. No `share_plus` dependency; an
`onShare` hook lets the host wire it up.

**Redaction was built, then removed.** I'd made it a hard prerequisite on the assumption that
reports get shared with other people. They don't — this is a personal tool, the output goes to
your own terminal, and a cURL command with the auth header scrubbed can't be replayed, which
is the entire reason you'd copy one. Everything is now captured and exported **verbatim**.

If the audience ever changes (shipped to non-employees, reports pasted into tickets), the
redactor is in git history and was straightforward: header denylist + exact-match body keys +
a text pass, applied at the escape points (`CopyButton`, `buildCurl`, `DebugReport`) rather
than at capture. Two things it taught, worth remembering if it comes back:
- Match body keys **exactly**, not by substring — `token` otherwise swallows `tokens`,
  `token_count`, `refresh_tokens_remaining`. Over-redaction silently destroys the data the
  tool exists to show.
- `key=value` needs handling too, not just `key: value` and `"key": "value"` — query strings
  and log lines use it.

<details>
<summary>Original design notes</summary>

### 3. Share / export bundle

One button: dump logs + network + errors + device info into a single text blob and hand it to
the OS share sheet. Turns "it broke on my phone" into a complete bug report.

### Design sketch
Reuse the `_asPlainText` serializers each page already has. Add a `share_plus` dependency (or
keep it dependency-free: write to a temp file and expose the path / just copy to clipboard).

### Cost
Small. It's the natural payoff of the copy-all buttons already there.

### Open questions
- **Redaction.** A dump like this will contain auth headers, tokens, and whatever PII is in
  response bodies. Right now that data never leaves memory; the moment we make sharing
  one-tap, it goes into Slack. **This needs a redaction hook before it ships** — e.g. a
  configurable `redactHeaders: {'authorization', 'cookie'}` and a `redactBody` callback.
  I'd treat this as a requirement, not a nice-to-have.
- Take the `share_plus` dependency, or stay dependency-free and just do clipboard + file path?

---

</details>

---

## 4. ~~Performance / FPS page~~ ✅ MOSTLY SHIPPED, as a Timeline lane

Built as the **jank lane on the Timeline** rather than its own page, because the interesting
question turned out not to be "what is the frame rate" but "what was the app doing when it
stalled" — and that is only answerable next to the network, log and state lanes.

Shipped: `DevtrayJank`, with `FreezeEvent` (the isolate stopped responding) and
`SlowFrameEvent` (a frame rendered, but late, with the build/raster split).

Decisions taken on the open questions:

- **Opt-in — yes.** `TimelineDebugPage(detectFreezes: true)`, or
  `DevtrayJank.instance.start()` for the whole session. It is the only capture in the
  overlay with a steady-state cost, so it is the only one that is off by default.
- **`addTimingsCallback` is not sufficient on its own.** It only fires for frames that
  *rendered*, so a three-second block produces no timings at all — the case you most want is
  the one it is blind to. A heartbeat timer covers that, and the two together cover both
  "we dropped 40 frames" and "we rendered nothing for a second".

The hard constraint, learned while building it: **a frozen isolate cannot detect its own
freeze.** No timer, frame callback or microtask runs while it is blocked. So detection is
retrospective, terminal hangs are reported by nothing, and there is no stack trace. Tapping a
freeze shows what else was happening in that window instead — labelled circumstantial, because
that is what it is.

Also worth recording, because it cost time: **the demo's stutter button did not work at
first.** It burned CPU between frames and yielded with `Future.delayed(Duration.zero)`, which
yields to the microtask queue rather than the rasteriser — so no frame ever rendered in the
gap. The result was a stutter you could feel and the tool could not see. The work has to run
inside a post-frame callback to land in `buildDuration`.

Still open, if it ever bites:
- **A sparkline / live FPS number.** The lane shows *when* jank happened; it does not show a
  rolling frame-rate. Nobody has wanted it yet.
- **Watchdog isolate.** The only way to catch a freeze *while it is happening*, including a
  terminal one. Real complexity (isolate lifecycle, spawn cost) and no web support, so not
  done until the retrospective version proves insufficient.

---

## 5. ~~Storage inspector~~ ✅ SHIPPED

Browse **and edit** key/value storage at runtime. `SharedPreferencesStorageAdapter` is built in
(free — already a dependency for mock-rule persistence); anything else is a
`DebugStorageAdapter`, ~15 lines.

Decisions taken:
- **Editing is per-field** (tap Edit → change → Save). A global edit-lock was built first, then
  removed: the per-field two-step is already deliberate enough, and the lock was just friction
  on top of it. `writable => false` on an adapter still hides the controls for a read-only store.
- **Types are preserved.** The control matches the value's existing type and writes that type
  back: bool → switch, **List → chips**, int/double → number field, String → text field.
  SharedPreferences has a setter *per type* and throws on the next read if you wrote the wrong
  one, so an editor that stringified everything would be a landmine. Bad input is rejected; the
  store is left untouched.
- **Lists are chips, not a JSON text area.** Tap to rename, ✕ to remove, `+` to add. Hand-editing
  `["flutter","dart"]` on a phone is the authoring-from-scratch problem we avoided in the mock
  editor, and it made *"Invalid JSON"* a failure reachable by mistyping a bracket. Manipulating
  each element directly makes a malformed list **unrepresentable**.
- **No bundled Hive adapter** (asked for, then talked out of it). It would add `hive` as a
  dependency for every user, and a *generic* adapter can't meaningfully edit typed model objects
  or open encrypted boxes anyway — which is exactly what Hapster has. The interface plus a
  README recipe gives real editing with neither problem.

Two bugs:
- `setState(() => _future = _load())` trips Flutter's "setState callback returned a Future"
  assertion — and so does `setState(() => _future = next)`, because the arrow body *returns* the
  future regardless of where it was built. It needs a block body.
- **Text fields in the panel couldn't be edited** — you could type, but backspace and the arrow
  keys did nothing. Typing goes through the platform text-input channel and works anywhere;
  backspace/arrows/select-all are *key bindings* resolved by the `Shortcuts`/`Actions` pair
  `WidgetsApp` installs, and the panel renders **above** `MaterialApp`, outside that scope.
  `_DebugToolsHost` now mirrors WidgetsApp's stack (`Shortcuts` → `DefaultTextEditingShortcuts`
  → `Actions` → `FocusTraversalGroup` → `TapRegionSurface`). This affected every text field in
  the tool — mock rule editor, search bars, storage editor — not just Storage.

<details>
<summary>Original design notes</summary>

### 5. Storage inspector

Browse **and edit** key-value storage. The editing is the killer feature: flip a value live
instead of rebuilding.

### Design sketch
Keep the core dependency-free with an adapter interface, exactly like `DeviceInfoProvider`:

```dart
abstract class DebugStorageAdapter {
  String get name;                          // tab/section label
  Future<Map<String, Object?>> readAll();
  Future<void> write(String key, Object? value);
  Future<void> delete(String key);
}
```

Ship a `SharedPreferencesStorageAdapter` built in. Users write ~15 lines for Hive, secure
storage, or their own.

### Cost
Medium. The adapter is easy; a **type-aware editor** (bool → switch, int → number field,
String → text, JSON → text with validation) is where the work is.

### Open questions
- Do we take a `shared_preferences` dependency for the built-in adapter, or ship only the
  interface and let users wire their own? (Same call we made for `device_info_plus` — we took
  the dep there.)
- Editing arbitrary values is a foot-gun: writing a malformed value could crash the app on
  next read. Confirm-before-write? Read-only by default with an "unlock" toggle?

---

</details>

---

## 6. Feature flags / overrides

A registry of named flags the app reads through, flippable at runtime. Pairs naturally with
the storage inspector.

### Design sketch
```dart
DebugFlags.register('new_checkout', defaultValue: false);
if (DebugFlags.of('new_checkout')) { ... }
```

Overlay page lists every registered flag with a switch. Overrides live in memory (or in the
storage adapter above, if that lands).

### Cost
Low — but it's only useful if the **app is written to read through it**, which is a bigger
ask than any other feature here. It changes the host app's code, not just its setup.

### Open questions
- Is this actually wanted, or does the app already have its own flag system? If it does, the
  right move is a **bridge** (like the logging bridge) rather than our own registry.

---

## 7. BLoC / state inspector

Live cubit state + transition history. Very high value in a BLoC codebase.

### Design sketch
A `BlocObserver` that feeds a store; page shows each bloc, its current state, and a scrolling
transition log. Essentially the Logs page with a different source.

### Cost
Medium.

### Open questions
- **This couples the package to `bloc`.** It should be a separate `devtray_bloc` add-on
  package so the core stays framework-agnostic — which means setting up a second package and
  a melos/workspace setup. Is that overhead worth it?
- A generic alternative: a `DebugPage` that renders any `ValueListenable`/`Stream` the app
  hands it. Weaker, but no coupling and no second package. Might be the better call.

---

## Cross-cutting concerns

Things that apply to several of the above and should be decided once:

- ~~**Redaction.**~~ Resolved: **not doing it.** See §3.
- ~~**Release safety.**~~ ✅ **Done — `DevtrayKillSwitch`.** Defaults to `kDebugMode`, so a
  release build captures nothing out of the box. When off: every store is a no-op, mocks never
  intercept (beats an active rule *and* offline mode), and whatever was already captured is
  cleared. `runDebugApp(enabled:)` drives it, so the UI and the capture can't drift apart.
  Critically, the interceptor stays a **passthrough** — disabling the tools cannot break the
  app's networking, and there's a test for exactly that.

  Side effect: `DevtrayLog.log()` and `ErrorStore.report()` now return `void` instead of the
  entry. Nothing used the return value, and a nullable one would have been noise.
- **Per-feature opt-in cost.** Performance capture is the first feature with a real
  steady-state cost. Worth a consistent story: which hooks are on by default, which are opt-in.

---

## Suggested order

1. ~~**Network mocking**~~ ✅ done.
2. ~~**Visual debug toggles (flags only)**~~ ✅ done.
3. ~~**Share/export**~~ ✅ done (redaction built then removed — not wanted).
4. ~~**Performance page**~~ ✅ done, as the Timeline's jank lane rather than its own page.
5. ~~**Storage inspector**~~ ✅ done.
6. Feature flags / BLoC inspector — both still need a decision on host-app coupling.

Not on the original list, built anyway:

- ~~**Timeline**~~ ✅ done. Requests, logs, state and jank on one time axis. It owns no data —
  every store already timestamps its entries, so it is a view over the existing three rather
  than a fourth to maintain. The idea came from noticing that nothing correlated the pages
  despite every one of them having the timestamps to do it.

Known gaps, recorded rather than fixed:

- **No cross-page navigation.** Tapping a request on the Timeline opens its detail *inline*
  rather than jumping to the Network tab, because there is no mechanism to jump: the
  `TabController` is private state and `DebugPage` has no identity. Adding one would unblock
  several other ideas (a failed request in the Logs page linking to the request that caused
  it, most obviously).
- **Slow-frame capture is untested end to end.** The widget-test environment reports no frame
  timings at all, so nothing in the suite can verify it. The arithmetic is tested and the
  example's jank buttons are the real verification — which is why it mattered that one of
  them was silently broken.
