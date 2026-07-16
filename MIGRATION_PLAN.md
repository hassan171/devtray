# Splitting `debug_overlay` into a core + integration packages

Status: **done.** The core has no dependencies beyond Flutter, and there are ten
packages. 261 tests pass, the same behaviour as before plus new guards.

`debug_overlay_riverpod` is the proof the split was worth it: a second
state-management binding, added afterwards, needed **zero changes to the core**.
Its tests also demonstrate bloc and Riverpod feeding the same page at once —
which is the payoff of keeping `StateDebugPage` in the core rather than shipping
one per library.

What actually shipped, against what was planned:

* **Nine packages, not seven.** `HiveStorage` and `SqfliteStorage` were promoted
  out of the example too — they imported only `debug_overlay` and their own
  library, so they were already packages in everything but name.
* **The test split was an improvement, not a tax.** The mock-rule logic never
  needed a real HTTP client; it only had one because the tests lived next to the
  adapters. Core's `mocking_test` now runs 18 tests with no client at all.
* **`status classification` moved to `_dio`**, though this plan filed it under
  logic — it tests dio's `onResponse` against `validateStatus`. Its own comment
  said "no mocking involved here", which was the tell.
* **`state_test` moved wholesale to `_bloc`**, rather than splitting: all 35 of
  its tests drive through `Bloc.observer`, and none touch `StateInspector`
  directly. That briefly left `StateDebugPage` untested in the core — the one
  thing the migration made worse — so `state_page_test.dart` now covers it with
  **no state library at all**, pushing straight into the inspector's public API.
  That's a better test than the one it replaces: it proves the claim the whole
  architecture rests on, rather than assuming it.

The rest of this document is the original plan, kept for the reasoning.

---

## Why

`debug_overlay` has 7 runtime dependencies, and every one exists to serve a
single integration:

| Dependency | Exists for | Wanted by |
|---|---|---|
| `dio` | `DebugDioInterceptor` | dio users |
| `http` | `DebugHttpClient` | http users |
| `bloc` | `DebugBlocObserver` | bloc users |
| `shared_preferences` | `SharedPreferencesStorageAdapter`, mock-rule persistence | some |
| `device_info_plus` + `package_info_plus` | `PluginDeviceInfoProvider` | Device page users |
| `flutter_html` | HTML response preview | rare |

So a Riverpod-and-`http` app today downloads and compiles **dio, bloc,
shared_preferences, device_info_plus, package_info_plus and flutter_html** for
nothing. The cost isn't download size — it's that every one of those is a version
constraint the host app doesn't control, and any of them can block *their*
upgrade.

## Why this is cheap

The architecture is already split; only the packaging isn't.

**Every dependency is confined to exactly one leaf file**, and **nothing in the
core imports those files** — only the barrel (`lib/debug_overlay.dart`)
re-exports them. Verified:

```
dio                → lib/src/network/adapters/dio_adapter.dart
http               → lib/src/network/adapters/http_adapter.dart
bloc               → lib/src/state/bloc_adapter.dart
shared_preferences → lib/src/storage/shared_preferences_storage_adapter.dart
                     lib/src/network/mocking/shared_preferences_mock_storage.dart
device_info_plus   → lib/src/device/plugin_device_info_provider.dart
package_info_plus  → (same file)
flutter_html       → lib/src/widgets/html_preview_dialog.dart
```

Each of those files exports exactly **one public class**. So for five of the six
packages this is `git mv` plus a pubspec — no logic changes at all.

## Target shape

A **pub workspace** (requires Dart 3.6+; we're on Flutter 3.44 ✓). One root
pubspec listing members, one shared lockfile, one `pub get`. No melos.

```
debug_overlay/                    ← workspace root (pubspec: workspace: [...])
  packages/
    debug_overlay/                ← core. ZERO runtime deps (+ the bundled font)
    debug_overlay_dio/            → dio
    debug_overlay_http/           → http
    debug_overlay_bloc/           → bloc
    debug_overlay_prefs/          → shared_preferences
    debug_overlay_device/         → device_info_plus, package_info_plus
    debug_overlay_html/           → flutter_html
  example/                        ← depends on all seven
```

Each integration package's `lib/<name>.dart` exports its one class and nothing
else. Core keeps the ~800KB JetBrains Mono asset — it's the one thing core does
carry, and it's what makes every page's data render identically.

## The two knots

Five of the six moves are mechanical. Two are not, because **the core currently
calls into them** — the dependency arrow points the wrong way and has to be
inverted first.

### 1. `flutter_html` — needs a hook (the only real API change)

`network_detail_pane.dart` calls `HtmlPreviewDialog.show(context, html)`
directly. Moving the file alone breaks the Network page.

**Fix:** invert it to a callback on the page.

```dart
// core
typedef DebugHtmlPreviewer = void Function(BuildContext context, String html);

class NetworkDebugPage extends DebugPage {
  /// Renders an HTML response body. Null hides the preview button — the core
  /// has no HTML renderer, by design.
  final DebugHtmlPreviewer? onPreviewHtml;
}

// host app, with debug_overlay_html installed
NetworkDebugPage(onPreviewHtml: HtmlPreviewDialog.show)
```

Without a hook the button doesn't render. Nothing breaks; the feature is absent,
which is honest.

**Breaking:** yes, for anyone relying on the preview button appearing by default.

### 2. `shared_preferences` — nearly free

`run_debug_app.dart:149` hard-wires `SharedPreferencesMockRuleStorage()`.

But **the seam already exists**: `MockStore.storage` is a `MockRuleStorage`
interface that already defaults to `InMemoryMockRuleStorage`. The core depends on
the abstraction today; only `run_debug_app`'s default wiring names the concrete
class.

**Fix:** delete the 2 lines that construct it, and flip `persistMockRules` to
default **false**.

```dart
// core — rules live for the session
runDebugApp(app: MyApp());

// + debug_overlay_prefs — rules survive hot restart
MockStore.instance.storage = SharedPreferencesMockRuleStorage();
runDebugApp(app: MyApp());
```

**Breaking:** yes, and worth calling out loudly in the CHANGELOG — mock rules
silently stop surviving hot restart unless the user opts in. That is exactly when
you're iterating on an error state, so the docs must be explicit.

## Tests

Only 4 of 13 test files touch a moving dependency:

| File | Uses | Goes to |
|---|---|---|
| `state_test.dart` | bloc | `debug_overlay_bloc/test/` |
| `kill_switch_test.dart` | dio | split: kill-switch logic stays in core (fake adapter); the dio assertions move |
| `mocking_test.dart` | **dio + http** | split per package (below) |
| `storage_test.dart` etc. | — | stay in core |

**`mocking_test.dart` is the awkward one** — it proves rules intercept through
*both* adapters, so it can't live in either package alone.

**Decision: split it.**
- The mock-rule **logic** (matching, regex, ordering, offline override, kill
  switch) stays in core, tested against a **fake adapter**. That's where the
  logic lives, and it needs no real HTTP client.
- The **interception** tests move to their own package: "a dio request hits a
  rule" → `debug_overlay_dio/test/`, likewise for http.

This is better than it sounds: it forces the core's mocking tests to stop
depending on a real HTTP client to test rule *matching*.

## Sequence

1. Scaffold the workspace: root `pubspec.yaml` with `workspace:`, move core into
   `packages/debug_overlay/`. Verify all 209 tests still pass — nothing else has
   changed yet.
2. Invert the two knots **in core, before moving anything**:
   - add `NetworkDebugPage.onPreviewHtml`, stop calling `HtmlPreviewDialog`;
   - drop the `SharedPreferencesMockRuleStorage` wiring, default
     `persistMockRules: false`.
   Core now imports neither `flutter_html` nor `shared_preferences`. Tests green.
3. Move the six leaf files into their packages, one at a time, each with its own
   pubspec + `lib/<name>.dart` barrel. Drop each dep from core's pubspec as its
   file leaves. Tests green after each.
4. Split the 4 test files per the table above.
5. Update `example/` to depend on all seven and wire the two hooks.
6. Update `README.md` — install instructions become per-integration, and the two
   breaking changes need documenting.
7. Full verify: `flutter test` in every member + `flutter build windows` on the
   example.

## Breaking changes (for the CHANGELOG)

1. **Adapters move to separate packages.** `DebugDioInterceptor`,
   `DebugHttpClient`, `DebugBlocObserver`, `SharedPreferencesStorageAdapter`,
   `SharedPreferencesMockRuleStorage`, `PluginDeviceInfoProvider` and
   `HtmlPreviewDialog` are no longer exported by `debug_overlay`. Add the
   matching `debug_overlay_*` dependency and import it.
2. **`persistMockRules` now defaults to `false`.** Mock rules are session-only
   unless you install `debug_overlay_prefs` and set `MockStore.instance.storage`.
3. **The Network page's HTML preview button is hidden by default.** Pass
   `NetworkDebugPage(onPreviewHtml: HtmlPreviewDialog.show)` from
   `debug_overlay_html` to restore it.

## Notes / risks

- **No external consumers.** `spot_line`/nawa no longer depends on
  `debug_overlay` (the integration was reverted), so this migration is purely
  internal: package + example + tests. Nothing downstream to coordinate.
- **Version lockstep.** Seven packages means every core change that touches a
  shared interface (`DebugStorageAdapter`, `MockRuleStorage`,
  `DeviceInfoProvider`) is a coordinated release. This is the real ongoing cost,
  and it's the thing to weigh against the benefit.
- **pub.dev discovery.** Six extra packages need descriptions/READMEs or they
  look abandoned. Not hard, but not free.
- **The example is the integration test.** It depends on everything, so if it
  builds, the wiring works. Keep it that way.
