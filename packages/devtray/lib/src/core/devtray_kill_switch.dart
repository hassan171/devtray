import 'package:flutter/foundation.dart';

/// The one switch that makes the whole package inert.
///
/// ## The gap this closes
///
/// `runDebugApp(enabled: false)` removes the *UI* — no overlay, no launcher, no
/// capture Zone. But the adapters are installed by **you**, not by the overlay:
///
/// ```dart
/// final dio = Dio()..interceptors.add(DebugDioInterceptor());   // ← always on
/// ```
///
/// So in a release build with that interceptor still in place, every request,
/// header and response body kept landing in `NetworkLogStore` — a rolling buffer
/// of 500 requests, auth tokens and all, held in memory with nothing to read it
/// and no reason to exist. Same for logs and errors.
///
/// ## Using it
///
/// [enabled] defaults to [kDebugMode], so a **release build captures nothing**
/// out of the box and you don't have to remember anything. Every store checks it
/// on write; mocks never intercept.
///
/// Override it to get the tools in a staging release:
///
/// ```dart
/// void main() {
///   const on = kDebugMode || bool.fromEnvironment('DEV_TOOLS');
///   DevtrayKillSwitch.enabled = on;
///   runDebugApp(const MyApp(), enabled: on, pages: [...]);
/// }
/// ```
///
/// Or flip it at runtime — a support build where the tools sit behind a login:
///
/// ```dart
/// DevtrayKillSwitch.enabled = user.isInternal;
/// ```
///
/// Switching it **off** also clears whatever the stores already hold (see
/// [addDisableListener]), so flipping it mid-session doesn't leave a buffer of
/// captured traffic behind.
class DevtrayKillSwitch {
  const DevtrayKillSwitch._();

  static bool _enabled = kDebugMode;

  /// When false, every store is a no-op and mocks never intercept.
  ///
  /// Defaults to [kDebugMode].
  static bool get enabled => _enabled;

  static set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      for (final listener in _disableListeners) {
        listener();
      }
    }
  }

  static final List<VoidCallback> _disableListeners = [];

  /// Called when the switch is turned **off**. The stores use this to drop what
  /// they've already captured — otherwise flipping the switch would leave the
  /// very buffer it exists to prevent.
  ///
  /// The stores register themselves; you shouldn't need this.
  static void addDisableListener(VoidCallback listener) => _disableListeners.add(listener);

  /// For tests — the switch is global, so a test that flips it would otherwise
  /// leak into every test after it.
  @visibleForTesting
  static void reset() => _enabled = kDebugMode;
}
