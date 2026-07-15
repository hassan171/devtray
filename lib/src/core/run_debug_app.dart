import 'package:flutter/material.dart';

import '../network/mocking/mock_store.dart';
import '../network/mocking/shared_preferences_mock_storage.dart';
import 'debug_capture.dart';
import 'debug_overlay_kill_switch.dart';
import 'debug_overlay.dart';
import 'debug_overlay_controller.dart';
import 'debug_overlay_theme.dart';
import 'debug_page.dart';

/// Installs log/error capture, wraps [app] in a [DebugOverlay], and runs it —
/// the whole setup in one call.
///
/// ```dart
/// void main() => runDebugApp(
///       const MyApp(),
///       enabled: kDebugMode,
///       pages: const [
///         NetworkDebugPage(),
///         LogsDebugPage(), // logs + errors in one filterable stream
///         DeviceDebugPage(provider: PluginDeviceInfoProvider()),
///       ],
///     );
/// ```
///
/// This is equivalent to calling [DebugOverlayCapture.runApp] and wrapping your
/// app in [DebugOverlay] by hand, except that [enabled] is stated once instead
/// of twice — a single switch for both the capture and the UI, which can't
/// drift out of sync.
///
/// When [enabled] is false this is exactly `runApp(app)`: no Zone, no hooks, no
/// overlay in the tree, nothing to strip for release.
///
/// **Why two things and not one widget?** The capturing Zone has to be
/// installed *around* `runApp`, and [DebugOverlay] is a widget that only exists
/// inside it. A widget cannot wrap its own `runApp` call — hence this function.
/// If you can't hand over your `runApp` (add-to-app, a custom bootstrap, tests),
/// use [DebugOverlayCapture] and [DebugOverlay] directly; see the README.
void runDebugApp(
  Widget app, {
  bool enabled = true,
  List<DebugPage> pages = const [],
  DebugOverlayController? controller,
  DebugOverlayPresentation presentation = DebugOverlayPresentation.dialog,
  DebugOverlayTheme theme = const DebugOverlayTheme(),
  bool showLauncher = true,
  bool showErrorBadge = true,
  DebugLauncherCorner launcherCorner = DebugLauncherCorner.bottomRight,
  EdgeInsets launcherMargin = const EdgeInsets.all(16),
  double launcherSize = 48,
  IconData launcherIcon = Icons.bug_report,
  Widget? launcherBuilder,

  /// Keep mock rules across restarts (via `shared_preferences`).
  ///
  /// On by default: you otherwise re-add "force /orders to 500" after every hot
  /// restart, which is exactly when you're iterating on an error state. Only
  /// the rules are stored — no logs, no request bodies.
  bool persistMockRules = true,
}) {
  // Drive the global switch from the same flag, so the UI and the capture can't
  // disagree. Without this, `enabled: false` would remove the overlay while the
  // adapters you installed kept buffering every request, token and body.
  DebugOverlayKillSwitch.enabled = enabled;

  if (!enabled) {
    // Not even a pass-through DebugOverlay in the tree — release builds get the
    // app exactly as they would without this package.
    runApp(app);
    return;
  }

  DebugOverlayCapture.runApp(
    () {
      // Don't restore rules into a store the app has turned off — they'd apply
      // with no UI to reveal them.
      if (persistMockRules && !MockStore.instance.isDisabled) {
        // Fire-and-forget: `rules` is a ValueNotifier, so the Mocks page picks
        // them up the moment they land. Awaiting here would mean holding up the
        // first frame for a debug tool's scratch file, which is a bad trade.
        MockStore.instance.storage = SharedPreferencesMockRuleStorage();
        MockStore.instance.load();
      }
      runApp(
        DebugOverlay(
          pages: pages,
          controller: controller,
          presentation: presentation,
          theme: theme,
          showLauncher: showLauncher,
          showErrorBadge: showErrorBadge,
          launcherCorner: launcherCorner,
          launcherMargin: launcherMargin,
          launcherSize: launcherSize,
          launcherIcon: launcherIcon,
          launcherBuilder: launcherBuilder,
          child: app,
        ),
      );
    },
  );
}
