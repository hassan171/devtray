# Changelog

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
