import 'package:flutter/foundation.dart';

import '../core/debug_overlay_kill_switch.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final int id;
  final DateTime time;
  final LogLevel level;
  final String message;

  /// Optional grouping label — a logger name, a subsystem, a feature.
  final String? tag;

  /// Present when the log came from an error report.
  final Object? error;
  final StackTrace? stackTrace;

  /// The `ErrorEntry` behind an error-level row, when this line was forwarded
  /// from [ErrorStore]. Typed as [Object?] so [LogStore] needn't import the
  /// errors layer (which imports back). The Logs page casts it to render the
  /// rich report on expand. Null for ordinary log lines.
  final Object? errorRef;

  const LogEntry({
    required this.id,
    required this.time,
    required this.level,
    required this.message,
    this.tag,
    this.error,
    this.stackTrace,
    this.errorRef,
  });

  bool get isError => errorRef != null;

  /// Everything a search should look at, lowercased once at match time.
  String get searchable => '$message ${tag ?? ''} ${error ?? ''}';
}

/// In-memory ring buffer of log lines, feeding [LogsDebugPage].
///
/// Capture is opt-in via [captureDebugPrint] (or the broader
/// `DebugOverlayCapture.installAll`), but you can always log directly:
///
/// ```dart
/// LogStore.instance.log('User signed in', level: LogLevel.info, tag: 'auth');
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

  int _nextId = 0;

  /// Newest first.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Distinct tags seen so far — drives the tag filter chips.
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
    Object? errorRef,
  }) {
    // The debugPrint/Zone hooks stay installed for the process lifetime, so
    // without this a release build would keep buffering 1000 log lines nothing
    // will ever read.
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
        errorRef: errorRef,
      ),
    );
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    tick.value++;
  }

  void clear() {
    _entries.clear();
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
