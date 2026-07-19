import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/devtray_kill_switch.dart';

/// A [ValueNotifier] whose value updates **synchronously** but whose listener
/// notifications are **coalesced onto a microtask**.
///
/// Why: the log store is fed from `FlutterError.onError`, which fires *during*
/// the build/layout/paint phase. A plain `ValueNotifier` would call its
/// listeners (a `ValueListenableBuilder`, marking it dirty) synchronously from
/// inside that phase — the "notify during build" hazard. When the same error
/// recurs every frame (a widget that re-throws on each rebuild), that becomes a
/// rebuild → re-throw → notify → rebuild loop that freezes the app.
///
/// Keeping the value assignment synchronous means reads (`.value`) are always
/// current — callers and tests that write then read see the new value at once.
/// Only the *notification* is deferred, and repeated writes in one turn collapse
/// into a single listener callback after the current stack unwinds.
class CoalescingValueNotifier<T> extends ChangeNotifier implements ValueListenable<T> {
  CoalescingValueNotifier(this._value);

  T _value;
  bool _notifyScheduled = false;

  @override
  T get value => _value;

  set value(T newValue) {
    if (_value == newValue) return;
    _value = newValue;
    _scheduleNotify();
  }

  /// Force a coalesced notification without changing [value] — used for the
  /// `tick` "something changed" signal where the value is just a counter.
  void bump() => _scheduleNotify();

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

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

  // Not `const`: [searchable] memoises into a mutable field. Nothing
  // constructed these as constants — the store is the only producer.
  LogEntry({
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

  /// Everything a search should look at, already lowercased.
  ///
  /// Computed once, lazily, and cached — a search pass touches every entry in
  /// the buffer, so building this string per entry per keystroke meant up to
  /// 1000 interpolations (each calling `toString()` on the error object, which
  /// for a `NetworkError` re-formats its method and URI) on every character
  /// typed. Lazy rather than eager so entries nobody ever searches don't pay.
  ///
  /// Safe to cache because every field it reads is final.
  String get searchable => _searchable ??= '$message ${tag ?? ''} ${error ?? ''} ${errorContext ?? ''}'.toLowerCase();
  String? _searchable;
}

/// In-memory ring buffer of log lines — the **single** store behind the Logs
/// page. Holds ordinary logs and reported errors alike; there is no separate
/// error store.
///
/// Capture is opt-in via [captureDebugPrint] / [captureErrors] (or the broader
/// [runDebugApp]), but you can always log or report directly:
///
/// ```dart
/// LogStore.instance.log('User signed in', level: LogLevel.info, tag: 'auth');
/// LogStore.instance.report(someException, stackTrace: s);
/// ```
class LogStore {
  LogStore._() {
    DevtrayKillSwitch.addDisableListener(clear);
  }
  static final LogStore instance = LogStore._();

  /// Oldest entries are dropped past this cap.
  int maxEntries = 1000;

  final List<LogEntry> _entries = [];

  /// A "something changed" signal for the Logs page. Coalesced: many entries
  /// added in one frame notify once (see [CoalescingValueNotifier]).
  final CoalescingValueNotifier<int> tick = CoalescingValueNotifier<int>(0);

  /// Number of **errors** recorded since the user last opened the Logs page.
  /// The launcher badge reads this — it's how an error that happened while
  /// nobody was looking still gets noticed. The value is current synchronously;
  /// only the listener notification is deferred off the build phase.
  final CoalescingValueNotifier<int> unseenErrorCount = CoalescingValueNotifier<int>(0);

  int _nextId = 0;

  /// Newest first.
  ///
  /// An unmodifiable *view*, not a copy — this is read inside a build, so
  /// `List.unmodifiable` was duplicating up to 1000 elements on every tick and
  /// every keystroke. The view wraps without allocating per element.
  List<LogEntry> get entries => UnmodifiableListView(_entries);

  /// Distinct tags currently in the buffer — drives the tag filter suggestions.
  ///
  /// Maintained incrementally instead of recomputed by walking all 1000 entries
  /// on every build. It's a *reference count*, not a plain set, so a tag still
  /// disappears once its last entry is evicted — suggesting a filter that
  /// cannot match anything would be worse than the walk it replaces.
  Set<String> get tags => UnmodifiableSetView(_tagCounts.keys.toSet());
  final Map<String, int> _tagCounts = {};

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
    final recorded = _add(
      message: error.toString(),
      level: LogLevel.error,
      tag: _sourceTag(source),
      error: error,
      stackTrace: stackTrace,
      source: source,
      errorContext: context,
      library: library,
    );
    // Only badge if the entry was actually recorded — with the kill switch off
    // _add is a no-op, and badging a launcher that isn't there would be a leak.
    // The value updates now; the listener callback is coalesced off the build
    // phase by CoalescingValueNotifier, so a mid-build report can't re-enter.
    if (recorded) unseenErrorCount.value++;
  }

  /// Records an entry. Returns false (a no-op) when the kill switch is off.
  bool _add({
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
    if (!DevtrayKillSwitch.enabled) return false;

    if (tag != null) _tagCounts.update(tag, (n) => n + 1, ifAbsent: () => 1);
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
      final evicted = _entries.removeLast().tag;
      if (evicted != null) {
        final remaining = (_tagCounts[evicted] ?? 1) - 1;
        if (remaining > 0) {
          _tagCounts[evicted] = remaining;
        } else {
          _tagCounts.remove(evicted);
        }
      }
    }
    // Never fire `tick`'s listeners inline — the report may be happening during
    // a build. `bump` coalesces into one deferred notification.
    tick.bump();
    return true;
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
    _tagCounts.clear();
    unseenErrorCount.value = 0;
    tick.bump();
  }
}

/// Original [debugPrint] handler, so capture can be undone.
DebugPrintCallback? _originalDebugPrint;

/// Routes [debugPrint] into [LogStore] — it keeps printing to the console too.
///
/// Bare `print()` cannot be intercepted this way; it needs a custom Zone. Use
/// [runDebugApp] (which installs one for you) if you want
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
/// use [runDebugApp], which installs the Zone for you.
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
