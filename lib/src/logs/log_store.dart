import 'package:flutter/foundation.dart';

import '../core/debug_overlay_kill_switch.dart';

enum LogLevel { debug, info, warning, error }

/// Where an error-level entry came from. Null on ordinary (non-error) log lines.
enum ErrorSource {
  /// A framework error — a build/layout/paint exception. Carries the widget
  /// ownership chain in [LogEntry.errorContext].
  flutter,

  /// An uncaught error on the platform dispatcher or in the app's Zone.
  uncaught,

  /// A failed HTTP request, forwarded from the Network page.
  network,

  /// Reported by the app via [LogStore.report].
  reported,
}

/// One line in the unified log stream.
///
/// A plain log has just a level/message/tag. An **error** carries the extra
/// fields too ([source], [errorContext], [library]) so the Logs page can render
/// a full report on expand — there is no separate error store. [isError]
/// distinguishes them.
class LogEntry {
  final int id;
  final DateTime time;
  final LogLevel level;
  final String message;

  /// Optional grouping label — a logger name, a subsystem, a feature. For an
  /// error this is its source name (`flutter` / `network` / …).
  final String? tag;

  /// The thrown object, when this line came from an error report. For a network
  /// failure it's a `NetworkError`.
  final Object? error;
  final StackTrace? stackTrace;

  /// Error metadata — set only for error-level entries reported via
  /// [LogStore.report]. Null for ordinary log lines.
  final ErrorSource? source;

  /// For Flutter errors: what the framework was doing ("building MyWidget").
  final String? errorContext;

  /// For Flutter errors: the widget ownership chain.
  final String? library;

  const LogEntry({
    required this.id,
    required this.time,
    required this.level,
    required this.message,
    this.tag,
    this.error,
    this.stackTrace,
    this.source,
    this.errorContext,
    this.library,
  });

  /// True for a reported error (as opposed to a plain log line) — it carries a
  /// [source] and the extra report fields.
  bool get isError => source != null;

  /// First line of the message — what a collapsed error row shows.
  String get title {
    final newline = message.indexOf('\n');
    return newline == -1 ? message : message.substring(0, newline);
  }

  /// Everything a search should look at, lowercased once at match time.
  String get searchable => '$message ${tag ?? ''} ${error ?? ''} ${errorContext ?? ''}';
}

/// In-memory ring buffer of log lines — the **single** store behind the Logs
/// page. Holds ordinary logs and reported errors alike; there is no separate
/// error store.
///
/// Capture is opt-in via [captureDebugPrint] / [captureErrors] (or the broader
/// `DebugOverlayCapture.installAll`), but you can always log or report directly:
///
/// ```dart
/// LogStore.instance.log('User signed in', level: LogLevel.info, tag: 'auth');
/// LogStore.instance.report(someException, stackTrace: s);
/// ```
class LogStore {
  LogStore._() {
    DebugOverlayKillSwitch.addDisableListener(clear);
  }
  static final LogStore instance = LogStore._();

  /// Oldest entries are dropped past this cap.
  int maxEntries = 1000;

  final List<LogEntry> _entries = [];
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// Number of **errors** recorded since the user last opened the Logs page.
  /// The launcher badge reads this — it's how an error that happened while
  /// nobody was looking still gets noticed.
  final ValueNotifier<int> unseenErrorCount = ValueNotifier<int>(0);

  int _nextId = 0;

  /// Newest first.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Distinct tags seen so far — drives the tag filter suggestions.
  Set<String> get tags => {
        for (final e in _entries)
          if (e.tag != null) e.tag!,
      };

  void log(
    String message, {
    LogLevel level = LogLevel.debug,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _add(message: message, level: level, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// Records an error into the stream — badging the launcher and carrying the
  /// full report fields so the Logs page can expand it.
  ///
  /// Framework/platform errors arrive here via [captureErrors]; network failures
  /// via the Network page; anything else you report yourself.
  void report(
    Object error, {
    StackTrace? stackTrace,
    ErrorSource source = ErrorSource.reported,
    String? context,
    String? library,
  }) {
    final message = error.toString();
    _add(
      message: message,
      level: LogLevel.error,
      tag: _sourceTag(source),
      error: error,
      stackTrace: stackTrace,
      source: source,
      errorContext: context,
      library: library,
    );
    unseenErrorCount.value++;
  }

  void _add({
    required String message,
    required LogLevel level,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    ErrorSource? source,
    String? errorContext,
    String? library,
  }) {
    // The debugPrint/Zone/error hooks stay installed for the process lifetime,
    // so without this a release build would keep buffering entries nothing will
    // ever read — and badging a launcher that isn't there.
    if (!DebugOverlayKillSwitch.enabled) return;

    _entries.insert(
      0,
      LogEntry(
        id: _nextId++,
        time: DateTime.now(),
        level: level,
        message: message,
        tag: tag,
        error: error,
        stackTrace: stackTrace,
        source: source,
        errorContext: errorContext,
        library: library,
      ),
    );
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    tick.value++;
  }

  static String _sourceTag(ErrorSource s) => switch (s) {
        ErrorSource.flutter => 'flutter',
        ErrorSource.uncaught => 'uncaught',
        ErrorSource.network => 'network',
        ErrorSource.reported => 'reported',
      };

  /// Called by the Logs page when it's shown — drops the launcher's error badge.
  void markErrorsSeen() => unseenErrorCount.value = 0;

  void clear() {
    _entries.clear();
    unseenErrorCount.value = 0;
    tick.value++;
  }
}

/// Original [debugPrint] handler, so capture can be undone.
DebugPrintCallback? _originalDebugPrint;

/// Routes [debugPrint] into [LogStore] — it keeps printing to the console too.
///
/// Bare `print()` cannot be intercepted this way; it needs a custom Zone. Use
/// `DebugOverlayCapture.installAll` (which wraps your app in one) if you want
/// those captured as well.
void captureDebugPrint() {
  if (_originalDebugPrint != null) return;
  _originalDebugPrint = debugPrint;

  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) LogStore.instance.log(message);
    _originalDebugPrint!(message, wrapWidth: wrapWidth);
  };
}

void stopCapturingDebugPrint() {
  if (_originalDebugPrint == null) return;
  debugPrint = _originalDebugPrint!;
  _originalDebugPrint = null;
}

bool _errorsCaptured = false;

/// Routes framework and platform errors into [LogStore], while still forwarding
/// them to whatever handler was already installed (so the red error screen and
/// console output are unaffected).
///
/// This catches [FlutterError.onError] and [PlatformDispatcher.onError].
/// Uncaught errors in async code outside the platform dispatcher need a Zone —
/// use `DebugOverlayCapture.installAll` for that.
void captureErrors() {
  if (_errorsCaptured) return;
  _errorsCaptured = true;

  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    LogStore.instance.report(
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
    LogStore.instance.report(error, stackTrace: stack, source: ErrorSource.uncaught);
    // Returning false lets the error keep propagating to the default handler,
    // which prints it — we observe, we don't swallow.
    return previousPlatformError?.call(error, stack) ?? false;
  };
}
