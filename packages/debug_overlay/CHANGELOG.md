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

   | Was in `debug_overlay` | Now in |
   |---|---|
   | `DebugDioInterceptor` | `debug_overlay_dio` |
   | `DebugHttpClient` | `debug_overlay_http` |
   | `DebugBlocObserver` | `debug_overlay_bloc` |
   | `SharedPreferencesStorageAdapter`, `SharedPreferencesMockRuleStorage` | `debug_overlay_prefs` |
   | `PluginDeviceInfoProvider` | `debug_overlay_device` |
   | `HtmlPreviewDialog` | `debug_overlay_html` |

2. **`persistMockRules` now defaults to `false`**, and needs a storage backend.

   Mock rules are session-only unless you wire one up — and they'll stop surviving hot
   restart silently, which is exactly when you're iterating on an error state. To restore
   the old behaviour:

   ```dart
   // + debug_overlay_prefs
   MockStore.instance.storage = SharedPreferencesMockRuleStorage();
   runDebugApp(app: const MyApp(), persistMockRules: true);
   ```

3. **The Network page's HTML preview button is hidden unless you supply a previewer.**

   The core can't render HTML any more, so a button would open nothing:

   ```dart
   // + debug_overlay_html
   NetworkDebugPage(onPreviewHtml: HtmlPreviewDialog.show)
   ```

   `onPreviewHtml` is a plain `void Function(BuildContext, String)` — pass your own renderer
   if you'd rather.

### Added

* `DebugHtmlPreviewer` — the hook type behind `NetworkDebugPage.onPreviewHtml`.

## 0.0.1

* Initial release.
