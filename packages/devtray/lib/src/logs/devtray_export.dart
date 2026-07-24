import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../core/devtray_facade.dart';
import '../network/devtray_net.dart';
import '../network/network_export.dart';
import 'devtray_log.dart';

/// Where captured logs go when they leave memory — a file, an upload, a
/// database, your own crash reporter.
///
/// [DevtrayLog] is a ring buffer: 1000 entries, oldest dropped, gone at process
/// exit. That's the right default for a debug overlay (it costs nothing and
/// leaks nothing), but it means the log of the crash you just saw dies with the
/// app. A sink is how you keep it.
///
/// The core deliberately ships **no** implementation. Writing a file needs
/// `dart:io` and a path — neither available on web, and the path is a decision
/// only the app can make (cache vs documents, encrypted or not). Uploading needs
/// an HTTP client, an endpoint, auth, and a judgement about what's allowed to
/// leave the device. So the core defines the shape and owns the batching, and
/// the transport is yours. `devtray_log_file` implements the file case.
///
/// ```dart
/// class UploadSink extends LogSink {
///   @override
///   Future<void> write(List<LogEntry> batch) async {
///     await dio.post('/logs', data: {'lines': batch.map(formatLogEntryAsJson).toList()});
///   }
/// }
///
/// DevtrayExport.instance.addSink(UploadSink());
/// ```
///
/// ## What a sink must guarantee
///
/// [write] is called with a batch and must not throw — a sink that throws is
/// disabled for the rest of the session (see [DevtrayExport]) rather than being
/// allowed to take down the app it's meant to be diagnosing. Handle your own
/// failures; return normally when you've done what you can.
///
/// It's called off the log call itself (see [FlushPolicy]), so it's free to be
/// slow. It is **not** free to be re-entrant: logging from inside [write]
/// re-enters the store and, with an immediate policy, recurses. Don't.
abstract class LogSink {
  const LogSink();

  /// A name for this sink, shown in the UI and in error messages.
  String get name;

  /// Persist a batch, oldest first.
  ///
  /// Ordering is chronological rather than the store's newest-first, because a
  /// log file read top-to-bottom should read forwards in time.
  Future<void> write(List<LogEntry> batch);

  /// Release anything held open. Called when the sink is removed, and on
  /// [DevtrayExport.dispose].
  Future<void> close() async {}
}

/// When buffered entries are handed to the sinks.
///
/// There's no single right answer, so this is a choice rather than a default
/// baked into the exporter:
///
/// * [immediate] loses nothing to a crash, and does I/O on every single log
///   line — on the UI isolate, in the middle of whatever was logging.
/// * [batched] does neither of those things reliably. It's the sane default.
/// * [manual] costs nothing in the background and loses everything to a crash.
///
/// A crash is exactly when the log matters most, which argues for [immediate];
/// a debug tool that makes the app stutter is a debug tool people turn off,
/// which argues against it. [batched] with a short interval is the compromise,
/// and flushing on app-pause (which [DevtrayExport.flushOnPause] does) recovers
/// most of what [immediate] would have bought.
sealed class FlushPolicy {
  const FlushPolicy();

  /// Write every entry as it arrives.
  ///
  /// Use when losing the last few lines is unacceptable and the sink is cheap.
  /// Expect a per-line cost on whatever thread called `log()`.
  const factory FlushPolicy.immediate() = ImmediateFlush;

  /// Write when [size] entries have accumulated, or [interval] has elapsed
  /// since the last flush — whichever comes first.
  ///
  /// The default. [interval] bounds how much a crash can lose; [size] bounds
  /// how much memory the pending buffer can hold when logging is fast.
  const factory FlushPolicy.batched({int size, Duration interval}) = BatchedFlush;

  /// Never flush on your behalf — [DevtrayExport.flush] is the only trigger.
  ///
  /// For "write a file when the user taps Export" and nothing else.
  const factory FlushPolicy.manual() = ManualFlush;
}

final class ImmediateFlush extends FlushPolicy {
  const ImmediateFlush();
}

final class BatchedFlush extends FlushPolicy {
  /// Flush once this many entries are pending.
  final int size;

  /// Flush at most this long after the first pending entry.
  final Duration interval;

  const BatchedFlush({this.size = 50, this.interval = const Duration(seconds: 5)});
}

final class ManualFlush extends FlushPolicy {
  const ManualFlush();
}

/// Fans captured logs out to any number of [LogSink]s, on a [FlushPolicy].
///
/// Nothing happens until you add a sink — an app that doesn't want persistence
/// pays for none of it, and [DevtrayLog] behaves exactly as before.
///
/// ```dart
/// DevtrayExport.instance
///   ..policy = const FlushPolicy.batched(size: 100, interval: Duration(seconds: 10))
///   ..addSink(await FileLogSink.open());
/// ```
///
/// ## Why this sits beside DevtrayLog rather than inside it
///
/// The store is a ring buffer with a cap; the exporter is a stream with none.
/// Every entry passes through here exactly once, *before* the store's eviction
/// can drop it — so a sink sees all 10,000 lines of a long session even though
/// the page only ever shows the last 1000. Putting export inside the store would
/// have tied what you keep on disk to what fits on screen.
class DevtrayExport {
  DevtrayExport._();
  static final DevtrayExport instance = DevtrayExport._();

  /// When pending entries are written. Changing it takes effect immediately;
  /// anything already pending is flushed under the new policy.
  FlushPolicy get policy => _policy;
  FlushPolicy _policy = const FlushPolicy.batched();

  set policy(FlushPolicy value) {
    _policy = value;
    _timer?.cancel();
    _timer = null;
    if (_pending.isNotEmpty) _schedule();
  }

  /// Flush whatever is pending when the app goes to the background.
  ///
  /// On by default, and the reason [FlushPolicy.batched] is a reasonable
  /// default: backgrounding is the last moment before the OS may kill the
  /// process, so it's the cheapest opportunity to not lose the buffer. Requires
  /// [DevtrayExport.observeLifecycle] to have been called — [runDebugApp] does it.
  bool flushOnPause = true;

  final List<LogSink> _sinks = [];

  /// Sinks that threw, and are no longer called. Kept so the UI can say *which*
  /// sink stopped working rather than silently dropping logs.
  final Map<String, Object> _failed = {};

  /// Entries captured but not yet written. Chronological (oldest first) —
  /// the opposite of [DevtrayLog.entries], because a file should read forwards.
  final List<LogEntry> _pending = [];

  Timer? _timer;
  bool _flushing = false;

  /// Sinks currently receiving logs.
  List<LogSink> get sinks => List.unmodifiable(_sinks);

  /// Sink name → the error that disabled it.
  Map<String, Object> get failedSinks => Map.unmodifiable(_failed);

  /// How many entries are waiting to be written.
  int get pendingCount => _pending.length;

  void addSink(LogSink sink) {
    _sinks.add(sink);
    _failed.remove(sink.name);
  }

  Future<void> removeSink(LogSink sink) async {
    _sinks.remove(sink);
    _failed.remove(sink.name);
    await sink.close();
  }

  /// Called by [DevtrayLog] for every recorded entry. Not part of the public API —
  /// log through [DevtrayLog.log] / [DevtrayLog.report] as usual.
  void ingest(LogEntry entry) {
    // No sinks means no buffer. Without this, an app that never configured
    // export would accumulate entries forever waiting for a flush that has
    // nowhere to go — a leak in the default configuration.
    if (_sinks.isEmpty) return;
    if (!Devtray.enabled) return;

    _pending.add(entry);
    _schedule();
  }

  void _schedule() {
    switch (_policy) {
      case ImmediateFlush():
        // Still deferred by a microtask: `ingest` can be called from inside a
        // build (FlutterError.onError), and starting async I/O synchronously
        // from there is the same hazard CoalescingValueNotifier exists to avoid.
        scheduleMicrotask(flush);

      case BatchedFlush(:final size, :final interval):
        if (_pending.length >= size) {
          scheduleMicrotask(flush);
        } else {
          // One timer per batch window, started by the first pending entry —
          // not restarted per entry, or a steady log stream would push the
          // deadline back forever and never flush.
          _timer ??= Timer(interval, flush);
        }

      case ManualFlush():
        break;
    }
  }

  /// Write everything pending to every healthy sink.
  ///
  /// Safe to call at any time, and safe to call concurrently — overlapping
  /// calls collapse, so a manual flush during a scheduled one doesn't write the
  /// same batch twice.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;

    if (_flushing || _pending.isEmpty) return;
    _flushing = true;

    // Taken before the await so entries logged *during* the write land in the
    // next batch rather than being dropped by the clear below.
    final batch = List<LogEntry>.of(_pending);
    _pending.clear();

    try {
      for (final sink in List<LogSink>.of(_sinks)) {
        if (_failed.containsKey(sink.name)) continue;
        try {
          await sink.write(batch);
        } catch (e) {
          // One bad sink must not stop the others, and must not throw into
          // whatever triggered the flush. Disable it and carry on — logging the
          // failure to the store, where it's visible on the page.
          _failed[sink.name] = e;
          DevtrayLog.instance.log(
            'Log sink "${sink.name}" failed and was disabled: $e',
            level: LogLevel.error,
            tag: 'devtray',
          );
        }
      }
    } finally {
      _flushing = false;
    }

    // Entries that arrived mid-write, or a policy change during it.
    if (_pending.isNotEmpty) _schedule();
  }

  /// Re-enable a sink that was disabled by a failure.
  void retrySink(String name) => _failed.remove(name);

  /// Start flushing when the app is backgrounded. Idempotent.
  ///
  /// [runDebugApp] calls this. Call it yourself if you wire the overlay up by
  /// hand and want [flushOnPause] to do anything.
  void observeLifecycle() {
    if (_lifecycleObserver != null) return;
    _lifecycleObserver = _LifecycleFlusher(this);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);
  }

  _LifecycleFlusher? _lifecycleObserver;

  /// Flush and close every sink.
  Future<void> dispose() async {
    await flush();
    for (final sink in List<LogSink>.of(_sinks)) {
      await sink.close();
    }
    _sinks.clear();
    _failed.clear();

    if (_lifecycleObserver case final observer?) {
      WidgetsBinding.instance.removeObserver(observer);
      _lifecycleObserver = null;
    }
  }
}

/// Flushes the exporter when the app leaves the foreground.
///
/// `paused` and `detached` are the last callbacks before the OS may kill the
/// process, so they're the cheapest moment to not lose the pending buffer —
/// which is what makes a batched policy safe enough to be the default.
class _LifecycleFlusher extends WidgetsBindingObserver {
  final DevtrayExport _exporter;
  _LifecycleFlusher(this._exporter);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_exporter.flushOnPause) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(_exporter.flush());
      // Requests still in flight, queued and written at the same moment — the
      // last one the OS reliably gives us. One observer for both, rather than a
      // second one racing it.
      DevtrayNetExport.instance
        ..flushPending()
        ..flush();
    }
  }
}

/// A past run the Logs page can offer to load.
///
/// Deliberately just an id, a label and two facts about size and age: the core
/// has no filesystem, so it can't know a session is a *file*. An implementation
/// backed by uploads, a database or an asset bundle is equally valid.
/// What the session picker needs of a saved run, whatever it holds.
///
/// Logs and requests are separate files with separate sources, but browsing
/// them is the same interaction — a list of runs, a size, a delete. This is the
/// slice the picker renders, so there is one picker rather than two that drift.
abstract class DevtraySessionInfo {
  /// What the picker shows. A timestamp reads best.
  String get label;

  /// Secondary line — a size, a count, whatever distinguishes one run.
  String? get detail;

  DateTime? get recordedAt;
}

/// A browsable set of saved runs, for the picker.
abstract class DevtraySessionSource<T extends DevtraySessionInfo> {
  Future<List<T>> list();

  /// Whether [delete] does anything. False hides the delete controls.
  bool get canDelete;

  Future<void> delete(T session);

  Future<void> deleteAll();
}

class LogSessionInfo implements DevtraySessionInfo {
  /// Opaque to the page — handed back to [LogSessionSource.load] unchanged.
  final String id;

  @override
  final String label;

  @override
  final String? detail;

  @override
  final DateTime? recordedAt;

  const LogSessionInfo({required this.id, required this.label, this.detail, this.recordedAt});
}

/// Supplies past sessions to the Logs page's session browser.
///
/// The seam that lets the page browse saved logs without the core knowing what
/// storage is. `devtray_log_file` implements it over files; anything that can
/// produce a list and parse entries back can implement it too.
///
/// ```dart
/// LogsDebugPage(sessionSource: DevtrayFileSessions(loader))
/// ```
abstract class LogSessionSource implements DevtraySessionSource<LogSessionInfo> {
  const LogSessionSource();

  /// Available sessions, newest first.
  @override
  Future<List<LogSessionInfo>> list();

  /// That session's entries, newest first — matching [DevtrayLog.entries], so the
  /// page renders either without knowing which it has.
  Future<List<LogEntry>> load(LogSessionInfo session);

  /// Whether [delete] does anything. False hides the delete controls.
  @override
  bool get canDelete => false;

  @override
  Future<void> delete(LogSessionInfo session) async {}

  /// Removes every session. Only offered when [canDelete].
  @override
  Future<void> deleteAll() async {}
}

/// One entry as a single line of JSON — the format the bundled file sink writes
/// and [parseLogEntries] reads back.
///
/// JSON Lines rather than one big JSON array: a line at a time means a crash
/// mid-write costs you the last line instead of making the whole file
/// unparseable, and appending never has to rewrite what's already there.
String formatLogEntryAsJson(LogEntry e) => jsonEncode({
      'id': e.id,
      'time': e.time.toIso8601String(),
      'level': e.level.name,
      'message': e.message,
      if (e.tag != null) 'tag': e.tag,
      if (e.source != null) 'source': e.source!.name,
      if (e.errorContext != null) 'context': e.errorContext,
      if (e.library != null) 'library': e.library,
      // Rendered, not retained: the thrown object isn't serialisable in general,
      // and by read-back time the type it came from may not even be in scope.
      if (e.error != null) 'error': e.error.toString(),
      // …with one exception. A NetworkError carries the whole request, and
      // flattening it to its one-line toString() destroyed exactly the detail a
      // saved session exists to preserve: the error detail pane checks
      // `case final NetworkError n`, which could never match a loaded session,
      // so every network error read back as a bare string.
      if (e.error case final NetworkError n) 'networkError': n.entry.toJson(),
      if (e.stackTrace != null) 'stack': e.stackTrace.toString(),
      // Rendered to strings rather than encoded as-is: a field can hold any
      // object, and one un-encodable value would otherwise fail the whole line.
      // The alternative — dropping the field silently — loses exactly the
      // context that was worth capturing.
      if (e.fields.isNotEmpty) 'fields': {for (final f in e.fields.entries) f.key: _fieldAsJson(f.value)},
    });

/// The error for a parsed entry: the structured request when one was written,
/// the rendered string otherwise.
///
/// A `NetworkError` is the one thrown object worth keeping whole — it carries
/// the request, and the detail pane renders it very differently from a bare
/// message.
Object? _errorFromJson(Map<String, Object?> json) {
  if (json['networkError'] case final Map raw) {
    return NetworkError(NetworkLogEntry.fromJson(Map<String, Object?>.from(raw)));
  }
  return json['error'] as String?;
}

/// A field value as something `jsonEncode` will accept.
///
/// Primitives pass through so numbers stay numbers on the way back; everything
/// else becomes its `toString()`, which always works.
Object? _fieldAsJson(Object? value) {
  if (value == null || value is num || value is bool || value is String) return value;
  return value.toString();
}

/// One entry as a plain human-readable line, for a sink that wants a log file
/// someone will open in a text editor rather than parse.
///
/// Not round-trippable — use [formatLogEntryAsJson] if you intend to load it
/// back into the overlay.
String formatLogEntryAsText(LogEntry e) {
  final tag = e.tag == null ? '' : ' [${e.tag}]';
  final buffer = StringBuffer('${e.time.toIso8601String()} ${e.level.name.toUpperCase().padRight(7)}$tag ${e.message}');
  // On the same line as the message: these are the values that make the line
  // mean something, and pushing them below makes the file read as pairs of
  // lines rather than a log.
  if (e.fields.isNotEmpty) buffer.write('  {${e.fieldsLabel}}');
  if (e.error != null) buffer.write('\n  error: ${e.error}');
  if (e.stackTrace != null) buffer.write('\n  ${e.stackTrace.toString().trimRight().replaceAll('\n', '\n  ')}');
  return buffer.toString();
}

/// Parses JSON-Lines log text back into entries, newest first.
///
/// Built to survive a damaged file, because the files worth reading are often
/// the ones the app died halfway through writing: an unparseable line is
/// skipped rather than failing the load, so a truncated final line costs you
/// that line and nothing else.
///
/// Returns newest-first to match [DevtrayLog.entries], so the same page can
/// render either without knowing which it has.
List<LogEntry> parseLogEntries(String contents) {
  final entries = <LogEntry>[];

  for (final line in const LineSplitter().convert(contents)) {
    if (line.trim().isEmpty) continue;

    try {
      final json = jsonDecode(line);
      if (json is! Map<String, dynamic>) continue;

      entries.add(
        LogEntry(
          id: json['id'] as int? ?? entries.length,
          time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
          level: LogLevel.values.firstWhere(
            (l) => l.name == json['level'],
            orElse: () => LogLevel.debug,
          ),
          message: json['message'] as String? ?? '',
          tag: json['tag'] as String?,
          // The structured request when there is one, so the detail pane can
          // render a loaded session's network error exactly like a live one.
          error: _errorFromJson(json),
          // A parsed stack is text, not a live StackTrace. Wrapped so the detail
          // pane can render it the same way it renders a real one.
          stackTrace: json['stack'] == null ? null : StackTrace.fromString(json['stack'] as String),
          source: json['source'] == null
              ? null
              : ErrorSource.values.firstWhere(
                  (s) => s.name == json['source'],
                  orElse: () => ErrorSource.reported,
                ),
          errorContext: json['context'] as String?,
          library: json['library'] as String?,
          fields: switch (json['fields']) {
            final Map<String, dynamic> f => Map<String, Object?>.from(f),
            _ => const {},
          },
        ),
      );
    } catch (_) {
      // A damaged line loses that line, not the file.
      continue;
    }
  }

  return entries.reversed.toList();
}
