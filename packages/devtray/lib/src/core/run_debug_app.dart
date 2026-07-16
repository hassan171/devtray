import 'dart:async';

import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';

/// Installs log/error capture, wraps [app] in a [Devtray], and runs it —
/// the whole setup in one call.
///
/// ```dart
/// void main() => runDebugApp(
///       app: const MyApp(),
///       enabled: kDebugMode,
///       pages: const [
///         NetworkDebugPage(),
///         LogsDebugPage(), // logs + errors in one filterable stream
///         DeviceDebugPage(provider: PluginDeviceInfoProvider()),
///       ],
///     );
/// ```
///
/// This is equivalent to installing the capture Zone and wrapping your app in
/// [Devtray] by hand, except that [enabled] is stated once instead of
/// twice — a single switch for both the capture and the UI, which can't drift
/// out of sync.
///
/// When [enabled] is false this is exactly `runApp(app)`: no Zone, no hooks, no
/// overlay in the tree, nothing to strip for release.
///
/// **Why two things and not one widget?** The capturing Zone has to be
/// installed *around* `runApp`, and [Devtray] is a widget that only exists
/// inside it. A widget cannot wrap its own `runApp` call — hence this function.
/// If you can't hand over your `runApp` (add-to-app, a custom bootstrap, tests),
/// install [captureErrors] / [captureDebugPrint] and [Devtray] yourself —
/// see the README.
///
/// ## Async bootstrap
///
/// Most real apps must initialise things before the first frame — Firebase,
/// notifications, a dotenv file, an orientation lock. That work has to run
/// **inside** the capturing Zone (so its errors and logs are captured too) and
/// **before** `runApp`. Pass it as [setup]; it is awaited before the app is
/// mounted, and it runs on both the enabled and disabled paths — your app boots
/// the same either way:
///
/// ```dart
/// void main() => runDebugApp(
///       app: const MyApp(),
///       enabled: kDebugMode,
///       setup: () async {
///         await Firebase.initializeApp();
///         await MyDotEnv.init();
///       },
///       pages: const [NetworkDebugPage(), LogsDebugPage()],
///     );
/// ```
///
/// [setup] runs after `WidgetsFlutterBinding.ensureInitialized()` and after the
/// capture hooks are installed, so a `debugPrint` or a thrown error during
/// bootstrap is already captured.
///
/// If your app widget can only be constructed *after* [setup] finishes (it
/// reads a value the bootstrap produced), pass [appBuilder] instead of [app] —
/// it is called after [setup] completes.
void runDebugApp({
  Widget? app,
  Widget Function()? appBuilder,
  Future<void> Function()? setup,
  bool enabled = true,
  List<DebugPage> pages = const [],
  DevtrayController? controller,
  DevtrayPresentation presentation = DevtrayPresentation.dialog,
  DevtrayTheme theme = const DevtrayTheme(),
  bool showLauncher = true,
  bool showErrorBadge = true,
  DebugLauncherCorner launcherCorner = DebugLauncherCorner.bottomRight,
  EdgeInsets launcherMargin = const EdgeInsets.all(16),
  double launcherSize = 48,
  IconData launcherIcon = Icons.bug_report,
  Widget? launcherBuilder,

  /// Route `FlutterError.onError` and `PlatformDispatcher.onError` into the Logs
  /// page (via [captureErrors]). Turn off if your app installs its own handlers
  /// and forwards to [LogStore] itself, to avoid double-reporting.
  bool captureFlutterErrors = true,

  /// Route `debugPrint` into the Logs page (via [captureDebugPrint]). Framework
  /// logs and most logging packages flow through `debugPrint`. Off = it prints
  /// as usual but isn't captured.
  bool captureDebugPrints = true,

  /// Route bare `print(...)` into the Logs page, via the Zone's print hook. Off
  /// = `print` behaves normally but isn't captured. Independent of
  /// [captureDebugPrints]: `print` and `debugPrint` are separate channels.
  bool captureZonePrints = true,

  /// Report uncaught errors that reach the Zone's error handler into the Logs
  /// page. Off = they still print to the console (never swallowed), just not
  /// captured — use it when your own `runZonedGuarded` already forwards them.
  bool captureUncaughtErrors = true,

  /// Called for every uncaught error that reaches the Zone's error handler —
  /// the `onError` of the internal `runZonedGuarded`. Use it to forward to your
  /// own crash reporter (Crashlytics, Sentry, a server log). Runs in addition to
  /// (not instead of) the built-in capture and console print; a throw inside it
  /// is swallowed so your handler can't take down the error path.
  void Function(Object error, StackTrace stack)? onUncaughtError,
}) {
  assert((app == null) != (appBuilder == null), 'Pass exactly one of `app` or `appBuilder`.');

  // Drive the global switch from the same flag, so the UI and the capture can't
  // disagree. Without this, `enabled: false` would remove the overlay while the
  // adapters you installed kept buffering every request, token and body.
  DevtrayKillSwitch.enabled = enabled;

  if (!enabled) {
    // Not even a pass-through Devtray in the tree — release builds get the
    // app exactly as they would without this package. The bootstrap still has
    // to run, so the app boots identically to the enabled path.
    if (setup == null) {
      runApp(app ?? appBuilder!());
      return;
    }
    WidgetsFlutterBinding.ensureInitialized();
    setup().then((_) => runApp(app ?? appBuilder!()));
    return;
  }

  runZonedGuarded(
    () async {
      // Must be inside the Zone: the binding latches onto the Zone it was
      // created in, and errors it reports would otherwise escape ours.
      WidgetsFlutterBinding.ensureInitialized();

      if (captureFlutterErrors) captureErrors();
      if (captureDebugPrints) captureDebugPrint();

      // Restore whatever the app's storage backend has, if any.
      //
      // No flag guards this, because installing a storage backend IS the opt-in:
      // `MockStore.storage` defaults to InMemoryMockRuleStorage, which is always
      // empty at startup, so this is a no-op until you set one. A separate
      // `persistMockRules` switch could only ever disagree with the storage you
      // chose.
      //
      // Skipped for a disabled store — restoring rules that can't intercept
      // would only populate a UI that isn't there.
      //
      // Fire-and-forget: `rules` is a ValueNotifier, so the Mocks page picks
      // them up the moment they land. Awaiting here would mean holding up the
      // first frame for a debug tool's scratch file, which is a bad trade.
      if (!MockStore.instance.isDisabled) MockStore.instance.load();

      // The app's own bootstrap — awaited inside the Zone so its logs and errors
      // are captured, and before `runApp` so the first frame sees a ready app.
      await setup?.call();

      runApp(
        Devtray(
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
          child: app ?? appBuilder!(),
        ),
      );
    },
    (error, stack) {
      if (captureUncaughtErrors) {
        LogStore.instance.report(error, stackTrace: stack, source: ErrorSource.uncaught);
      }
      // The app's own hook — e.g. forward to Crashlytics. Guarded so a throw in
      // the reporter can't cascade into the Zone's error handling.
      if (onUncaughtError != null) {
        try {
          onUncaughtError(error, stack);
        } catch (_) {}
      }
      // Keep the default behaviour — print it. Without this the Zone would
      // silently eat every uncaught error, which is far worse than the bug
      // we're trying to observe. This runs regardless of capture, so nothing is
      // swallowed.
      Zone.root.print('Uncaught (in debug overlay zone): $error\n$stack');
    },
    // Only intercept `print` when we're actually capturing it — otherwise leave
    // the Zone's print untouched so lines just print normally.
    zoneSpecification: captureZonePrints
        ? ZoneSpecification(
            print: (self, parent, zone, line) {
              LogStore.instance.log(line);
              parent.print(zone, line);
            },
          )
        : null,
  );
}
