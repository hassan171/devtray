import 'dart:async';

import 'package:flutter/widgets.dart';

import '../errors/error_store.dart';
import '../logs/log_store.dart';

/// One-call setup for the self-capturing pages (Logs and Errors).
///
/// ```dart
/// void main() => DebugOverlayCapture.runApp(
///       () => runApp(const MyApp()),
///       enabled: kDebugMode,
///     );
/// ```
///
/// This installs, in order:
/// - a Zone that captures bare `print()` and uncaught async errors,
/// - [FlutterError.onError] → the Errors page,
/// - [PlatformDispatcher.onError] → the Errors page,
/// - a [debugPrint] hook → the Logs page.
///
/// **You do not have to use it.** Calling [captureDebugPrint] and
/// [captureErrors] yourself gets you everything except bare `print()` and
/// uncaught async errors — those two genuinely require the Zone, which means
/// owning the `runApp` call.
///
/// Nothing here swallows anything: errors still reach the console and the red
/// error screen, and prints still print.
class DebugOverlayCapture {
  const DebugOverlayCapture._();

  /// Runs [body] (which should call `runApp`) inside a capturing Zone.
  ///
  /// When [enabled] is false this is a plain passthrough — no Zone, no hooks,
  /// zero overhead — so it's safe to leave in a release build.
  static void runApp(void Function() body, {bool enabled = true}) {
    if (!enabled) {
      body();
      return;
    }

    runZonedGuarded(
      () {
        // Must be inside the Zone: the binding latches onto the Zone it was
        // created in, and errors it reports would otherwise escape ours.
        WidgetsFlutterBinding.ensureInitialized();
        installHooks();
        body();
      },
      (error, stack) {
        ErrorStore.instance.report(error, stackTrace: stack, source: ErrorSource.uncaught);
        // Keep the default behaviour — print it. Without this the Zone would
        // silently eat every uncaught error, which is far worse than the bug
        // we're trying to observe.
        Zone.root.print('Uncaught (in debug overlay zone): $error\n$stack');
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          LogStore.instance.log(line);
          parent.print(zone, line);
        },
      ),
    );
  }

  /// Installs the non-Zone hooks: [captureErrors] and [captureDebugPrint].
  ///
  /// Idempotent, and each hook chains to whatever was already installed. Call
  /// this directly if you'd rather not hand [runApp] over to the overlay.
  static void installHooks() {
    captureErrors();
    captureDebugPrint();
  }
}
