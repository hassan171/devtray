import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/devtray_context.dart';
import '../core/devtray_facade.dart';
import '../core/devtray_typedefs.dart';
import 'devtray_export.dart';

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

  /// Reported by the app via [DevtrayLog.report].
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
  /// [DevtrayLog.report]. Null for ordinary log lines.
  final ErrorSource? source;

  /// For Flutter errors: what the framework was doing ("building MyWidget").
  final String? errorContext;

  /// For Flutter errors: the widget ownership chain.
  final String? library;

  /// Structured context carried alongside the message — a user id, the current
  /// screen, a cart total, a build number.
  ///
  /// Three sources merge into this at capture time, later winning over earlier:
  ///
  /// 1. [DevtrayLog.context] — ambient values set once and attached to everything
  /// 2. [DevtrayLog.addEnricher] — callbacks computed per entry
  /// 3. the `fields:` argument on the individual [DevtrayLog.log] call
  ///
  /// So a call-site field always beats an enricher, which always beats ambient
  /// context. That order is the useful one: the more specific the source, the
  /// more it knows.
  ///
  /// Empty (and shared, so free) when nothing is configured.
  final Map<String, Object?> fields;

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
    this.fields = const {},
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
  String get searchable => _searchable ??= [
    message,
    tag ?? '',
    '${error ?? ''}',
    errorContext ?? '',
    // Both halves: you search for `userId` as often as for the value, and
    // "the log line that mentions 4821" is the more common of the two.
    for (final e in fields.entries) '${e.key} ${e.value}',
  ].join(' ').toLowerCase();
  String? _searchable;

  /// [fields] rendered as `key=value` pairs — for a row subtitle or a copied
  /// report, where a Map's `toString()` braces are noise.
  String get fieldsLabel => fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
}

/// In-memory ring buffer of log lines — the **single** store behind the Logs
/// page. Holds ordinary logs and reported errors alike; there is no separate
/// error store.
///
/// Capture is opt-in via [captureDebugPrint] / [captureErrors] (or the broader
/// [runDebugApp]), but you can always log or report directly:
///
/// ```dart
/// DevtrayLog.instance.log('User signed in', level: LogLevel.info, tag: 'auth');
/// DevtrayLog.instance.report(someException, stackTrace: s);
/// ```
///
/// ## Carrying context
///
/// A line saying "request failed" is worth much less than one that also says
/// who it happened to, on which screen, on which build. Three ways to attach
/// that, composing least-specific to most:
///
/// ```dart
/// // Ambient — set once, on everything after.
/// DevtrayLog.instance.setContext('userId', user.id);
///
/// // Computed — fresh per entry, for values that must be current.
/// DevtrayLog.instance.addEnricher('nav', () => {'screen': router.current});
///
/// // Per-call — one line only.
/// DevtrayLog.instance.log('Checkout failed', fields: {'cartId': 42});
/// ```
///
/// All three land in [LogEntry.fields], are searchable, filterable, and are
/// written by the log sinks. The payoff is the errors you *didn't* anticipate:
/// [captureErrors] reports a crash you never wrote a handler for, and ambient
/// context is what makes that report say whose crash it was.
///
/// See [context], [addEnricher] and [LogEntry.fields].
class DevtrayLog {
  DevtrayLog._() {
    Devtray.addDisableListener(clear);

    // The context registry is store-agnostic on purpose, so it cannot log. This
    // is the one place that knows how — a dropped enricher becomes an ordinary
    // error line on the Logs page rather than vanishing.
    DevtrayContext.instance.onEnricherDropped = (message) => log(message, level: LogLevel.error, tag: 'devtray');
  }
  static final DevtrayLog instance = DevtrayLog._();

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

  /// Values attached to **every** entry from now on.
  ///
  /// For the facts that are true of a whole span of the session rather than of
  /// one line — who's signed in, which build, which screen. Set them once and
  /// every log line and error carries them, with no call site to remember:
  ///
  /// ```dart
  /// DevtrayLog.instance.setContext('userId', user.id);
  /// DevtrayLog.instance.setContext('build', '1.4.2+318');
  /// ```
  ///
  /// The point is errors you didn't anticipate. A crash report that says *who*
  /// it happened to and *what build* they were on is a different object from
  /// one that doesn't, and you can't retrofit that at the throw site.
  ///
  /// Read-only here — mutate through [setContext] / [removeContext] /
  /// [clearContext], which keep the snapshot sharing in [_snapshotContext]
  /// correct.
  /// The ambient values carried by every entry.
  ///
  /// Lives on [DevtrayContext] now, shared with [DevtrayNet] so a *request* can
  /// say which screen fired it too. These stay as the log store's own API
  /// because that is where they have always been documented, and because
  /// `Devtray.setContext` is the route most call sites use.
  Map<String, Object?> get context => DevtrayContext.instance.values;

  /// Adds or replaces one ambient value.
  void setContext(String key, Object? value) => DevtrayContext.instance.set(key, value);

  /// Adds or replaces several at once.
  void setContextAll(Map<String, Object?> values) => DevtrayContext.instance.setAll(values);

  void removeContext(String key) => DevtrayContext.instance.remove(key);

  void clearContext() => DevtrayContext.instance.clear();

  /// Runs [body] with extra ambient values, then restores what was there.
  ///
  /// ```dart
  /// await DevtrayLog.instance.withContext({'orderId': id}, () async {
  ///   await submitOrder();   // every line in here carries orderId
  /// });
  /// ```
  ///
  /// Restores previous values rather than deleting the keys, so nesting works
  /// and an inner scope can shadow an outer one. Not re-entrant across
  /// concurrent async work — two overlapping `withContext` calls on the same
  /// key will interleave, because this is one shared map rather than Zone
  /// state. For per-request isolation, pass the field explicitly instead.
  Future<T> withContext<T>(Map<String, Object?> values, Future<T> Function() body) => DevtrayContext.instance.withValues(values, body);

  /// Registers a callback that adds fields to every entry, computed fresh.
  ///
  /// Runs on **every** capture — log lines *and* network requests — so keep it
  /// cheap: this is not the place for a platform channel call or a database
  /// read. If it throws, the failure is recorded as the field's value and the
  /// entry still lands; after repeated failures the enricher is dropped and a
  /// line is logged saying so. A broken enricher must never cost you the entry
  /// it was decorating.
  ///
  /// Registering the same [name] twice replaces the first.
  void addEnricher(String name, DevtrayEnricher compute) => DevtrayContext.instance.addEnricher(name, compute);

  void removeEnricher(String name) => DevtrayContext.instance.removeEnricher(name);

  /// Drops every registered enricher.
  ///
  /// Mostly for tests — the registry is global, so a registration made in one
  /// would otherwise decorate every entry in the next.
  @visibleForTesting
  void clearEnrichers() => DevtrayContext.instance.clearEnrichers();

  /// Enricher name → the error that disabled it.
  Map<String, Object> get failedEnrichers => DevtrayContext.instance.failedEnrichers;

  void log(
    String message, {
    LogLevel level = LogLevel.debug,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    _add(message: message, level: level, tag: tag, error: error, stackTrace: stackTrace, fields: fields);
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
    Map<String, Object?>? fields,
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
      fields: fields,
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
    Map<String, Object?>? fields,
  }) {
    // The debugPrint/Zone/error hooks stay installed for the process lifetime,
    // so without this a release build would keep buffering entries nothing will
    // ever read — and badging a launcher that isn't there.
    if (!Devtray.enabled) return false;

    if (tag != null) _tagCounts.update(tag, (n) => n + 1, ifAbsent: () => 1);

    final entry = LogEntry(
      fields: DevtrayContext.instance.resolve(fields),
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
    );

    // Handed to the sinks BEFORE the ring buffer can evict anything, so a long
    // session writes every line to disk even though the page only ever holds
    // the last [maxEntries]. No-ops when no sink is configured.
    DevtrayExport.instance.ingest(entry);

    _entries.insert(0, entry);
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

/// Routes [debugPrint] into [DevtrayLog] — it keeps printing to the console too.
///
/// Bare `print()` cannot be intercepted this way; it needs a custom Zone. Use
/// [runDebugApp] (which installs one for you) if you want
/// those captured as well.
void captureDebugPrint() {
  if (_originalDebugPrint != null) return;
  _originalDebugPrint = debugPrint;

  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) DevtrayLog.instance.log(message);
    _originalDebugPrint!(message, wrapWidth: wrapWidth);
  };
}

void stopCapturingDebugPrint() {
  if (_originalDebugPrint == null) return;
  debugPrint = _originalDebugPrint!;
  _originalDebugPrint = null;
}

bool _errorsCaptured = false;

/// Routes framework and platform errors into [DevtrayLog], while still forwarding
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
    DevtrayLog.instance.report(
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
    DevtrayLog.instance.report(error, stackTrace: stack, source: ErrorSource.uncaught);
    // Returning false lets the error keep propagating to the default handler,
    // which prints it — we observe, we don't swallow.
    return previousPlatformError?.call(error, stack) ?? false;
  };
}
