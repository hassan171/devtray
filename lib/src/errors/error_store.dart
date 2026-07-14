import 'package:flutter/foundation.dart';

import '../core/debug_overlay_kill_switch.dart';

/// Where a caught error came from.
enum ErrorSource {
  /// A framework error — a build/layout/paint exception. Carries the widget
  /// ownership chain in [ErrorEntry.context].
  flutter,

  /// An uncaught error on the platform dispatcher or in the app's Zone.
  uncaught,

  /// A failed HTTP request, forwarded from the Network page.
  network,

  /// Reported by the app via [ErrorStore.report].
  manual,
}

class ErrorEntry {
  final int id;
  final DateTime time;
  final ErrorSource source;
  final Object error;
  final StackTrace? stackTrace;

  /// For Flutter errors: what the framework was doing ("building MyWidget").
  final String? context;

  /// For Flutter errors: the widget ownership chain.
  final String? library;

  const ErrorEntry({
    required this.id,
    required this.time,
    required this.source,
    required this.error,
    this.stackTrace,
    this.context,
    this.library,
  });

  /// First line of the exception — what the list row shows.
  String get title {
    final s = error.toString();
    final newline = s.indexOf('\n');
    return newline == -1 ? s : s.substring(0, newline);
  }
}

/// Collects uncaught and framework errors so they can be reviewed on-device,
/// long after the console has scrolled past them.
///
/// Install the hooks with [captureErrors] (or `DebugOverlayCapture.installAll`).
class ErrorStore {
  ErrorStore._() {
    DebugOverlayKillSwitch.addDisableListener(clear);
  }
  static final ErrorStore instance = ErrorStore._();

  int maxEntries = 200;

  final List<ErrorEntry> _entries = [];
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// Number of errors recorded since the user last opened the Errors page.
  /// The launcher badge reads this — it's how an error that happened while
  /// nobody was looking still gets noticed.
  final ValueNotifier<int> unseenCount = ValueNotifier<int>(0);

  int _nextId = 0;

  /// Newest first.
  List<ErrorEntry> get entries => List.unmodifiable(_entries);

  void report(
    Object error, {
    StackTrace? stackTrace,
    ErrorSource source = ErrorSource.manual,
    String? context,
    String? library,
  }) {
    // FlutterError.onError and the Zone handler stay installed for the process
    // lifetime — without this a release build would keep buffering errors, and
    // badging a launcher that isn't there.
    if (!DebugOverlayKillSwitch.enabled) return;

    _entries.insert(
      0,
      ErrorEntry(
        id: _nextId++,
        time: DateTime.now(),
        source: source,
        error: error,
        stackTrace: stackTrace,
        context: context,
        library: library,
      ),
    );
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    unseenCount.value++;
    tick.value++;
  }

  /// Called by the Errors page when it's shown.
  void markAllSeen() => unseenCount.value = 0;

  void clear() {
    _entries.clear();
    unseenCount.value = 0;
    tick.value++;
  }
}

bool _errorsCaptured = false;

/// Routes framework and platform errors into [ErrorStore], while still
/// forwarding them to whatever handler was already installed (so the red error
/// screen and console output are unaffected).
///
/// This catches [FlutterError.onError] and [PlatformDispatcher.onError].
/// Uncaught errors in async code outside the platform dispatcher need a Zone —
/// use `DebugOverlayCapture.installAll` for that.
void captureErrors() {
  if (_errorsCaptured) return;
  _errorsCaptured = true;

  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    ErrorStore.instance.report(
      details.exception,
      stackTrace: details.stack,
      source: ErrorSource.flutter,
      context: details.context?.toString(),
      library: details.library,
    );
    previousFlutterError?.call(details);
  };

  final previousPlatformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    ErrorStore.instance.report(error, stackTrace: stack, source: ErrorSource.uncaught);
    // Returning false lets the error keep propagating to the default handler,
    // which prints it — we observe, we don't swallow.
    return previousPlatformError?.call(error, stack) ?? false;
  };
}
