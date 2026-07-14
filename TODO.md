# debug_overlay — roadmap

Candidate features, with enough design detail to argue about. Each one lists what it does,
how it'd be built, what it costs, and the **open questions** that need a decision before
writing code.

Ordered by value-per-effort. Nothing here is committed.

**Shipped so far:** Network, **Mocks**, Logs, Errors, Device pages · pluggable `DebugPage`
system · `runDebugApp` one-call setup · dio + http adapters · network→errors forwarding.

**Explicitly not doing:** persistence across restarts. In-memory only is a defensible
default, and the crash-forensics case isn't worth the machinery (batched disk writer, size
caps, redaction of tokens/PII that currently just evaporate). Revisit only if the "what
killed it last time" question actually bites.

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
`MockStore.instance.disable()` stops interception for real (beats offline mode, every rule,
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
A rule list on `NetworkLogStore`, applied by the adapters — the same shape as the
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

NetworkLogStore.instance.mockRules.value = [...];
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

## 2. Visual debug toggles — best value-per-hour

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
app's tree, which means `DebugOverlay` would have to inject a `MediaQuery`/`Localizations`
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

---

## 3. Share / export bundle

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

## 4. Performance / FPS page

Self-capturing, zero integration cost, answers "is this screen janking" without a desktop.

### What it does
- Frame **build** and **raster** times via `SchedulerBinding.instance.addTimingsCallback`
- A rolling sparkline of the last N frames
- A **jank counter** (frames over 16ms / 33ms), and worst-frame stats
- Optionally: a live FPS number

### Design sketch
A `PerformanceStore` in the same mold as the others — ring buffer of `FrameTiming`s, fed by a
timings callback registered in `DebugOverlayCapture.installHooks()`. Page renders a
`CustomPainter` sparkline.

### Cost
Low-medium. The capture is a few lines. The sparkline is a small `CustomPainter`.

### Open questions
- The callback fires **every frame**, so the store must be cheap — a fixed-size circular
  buffer of raw microsecond ints, no allocation per frame, and the *page* does the math only
  while it's visible. Worth being disciplined here or the profiler becomes the jank.
- Should capture be opt-in (a flag on `installHooks`)? Leaning yes — it's the only feature
  with a real steady-state cost.

---

## 5. Storage inspector

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
- **This couples the package to `bloc`.** It should be a separate `debug_overlay_bloc` add-on
  package so the core stays framework-agnostic — which means setting up a second package and
  a melos/workspace setup. Is that overhead worth it?
- A generic alternative: a `DebugPage` that renders any `ValueListenable`/`Stream` the app
  hands it. Weaker, but no coupling and no second package. Might be the better call.

---

## Cross-cutting concerns

Things that apply to several of the above and should be decided once:

- **Redaction.** Needed by *Share/export* (hard requirement) and arguably by Network already.
  A single `DebugRedactor` (header allowlist/denylist + body callback) used everywhere would
  be cleaner than solving it per-feature.
- **Release safety.** `enabled: false` disables the UI, but adapters keep recording and mocks
  would keep mocking. Consider a single global kill switch that makes every store a no-op.
- **Per-feature opt-in cost.** Performance capture is the first feature with a real
  steady-state cost. Worth a consistent story: which hooks are on by default, which are opt-in.

---

## Suggested order

1. ~~**Network mocking**~~ ✅ done.
2. **Visual debug toggles (flags only)** — an hour's work, immediately useful. ← next
3. **Share/export** — small, *but only after the redaction hook exists*.
4. **Performance page** — self-capturing, no integration cost.
5. Storage / flags / BLoC — all need a decision about how much host-app coupling we want.
