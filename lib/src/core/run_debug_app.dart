import 'package:flutter/material.dart';

import 'debug_capture.dart';
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
///         LogsDebugPage(),
///         ErrorsDebugPage(),
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
}) {
  if (!enabled) {
    // Not even a pass-through DebugOverlay in the tree — release builds get the
    // app exactly as they would without this package.
    runApp(app);
    return;
  }

  DebugOverlayCapture.runApp(
    () => runApp(
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
    ),
  );
}
