import 'package:devtray/devtray.dart';
import 'package:devtray_dio/devtray_dio.dart';
import 'package:devtray_http/devtray_http.dart';
import 'package:devtray_log_file/devtray_log_file.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import 'counter_cubit.dart';

/// The app's long-lived objects.
///
/// In their own file rather than in `main.dart` so the screens can reach them
/// without importing the file that imports *them* — a cycle Dart allows but
/// nobody enjoys reading.
///
/// A real app would inject these (Riverpod providers, get_it, an InheritedWidget).
/// Globals here keep the example's wiring visible in one place, which is what
/// the example is for.

/// The one interceptor is all the Network page needs — every request made
/// through this client shows up, including the ones the app makes on its own.
final dio = Dio()..interceptors.add(DebugDioInterceptor());

/// The same, for `package:http`. Both transports feed one page.
final httpClient = DebugHttpClient(http.Client());

/// Live state sources, so the State page has something to watch.
final counter = CounterCubit();
final todos = TodoBloc();

/// Reads saved log sessions back. Set by [installLogPersistence]; null until
/// then, which is what the Logs page checks before offering the picker.
LogSessionLoader? logSessions;

/// Starts writing captured logs to disk, and returns the source the Logs page
/// browses them with.
///
/// The whole opt-in is `addSink` — before it, [DevtrayLog] behaves exactly as it
/// always has and nothing is written anywhere.
/// Opens the rotating file sink, and remembers where it wrote so the Logs
/// page's session picker can read those files back.
///
/// Called from `configure`'s `logToAsync`, which awaits it before the app runs
/// — so a line logged during bootstrap still lands in the file.
Future<LogSink> openFileLogSink() async {
  final sink = await FileLogSink.open(
    // Documents rather than the cache default: this example is *about* showing
    // the files, and cache directories can be evicted by the OS between runs.
    // A real app logging for its own diagnostics wants the cache default.
    location: LogFileLocation.documents,
    // Small, so the example actually rotates — the load generator crosses this
    // in a few seconds. A real app wants megabytes.
    maxBytes: 64 * 1024,
    maxFiles: 8,
  );

  // The session browser reads from wherever the sink decided to write, so it
  // can only be wired up once the sink is open.
  logSessions = LogSessionLoader(sink.directory);
  return sink;
}

/// When the app started, for the `session` enricher registered in main().
final DateTime startedAt = DateTime.now();

/// Which screen the app is on, read by the `nav` enricher above.
///
/// A global for the example's sake; a real app reads this from its router.
String currentScreen = 'bootstrap';

/// Bridges the gap between `pages:` (built synchronously in `main`) and the log
/// directory (opened asynchronously during bootstrap).
///
/// The same problem the storage adapters solve by being passed as a mutable
/// list. A source rather than a list here, because [LogsDebugPage] wants one
/// object — so this one just forwards to [logSessions] once it exists, and
/// reports empty until then.
///
/// A real app that already knows its paths, or that awaits its bootstrap before
/// calling `runDebugApp`, hands over `DevtrayFileSessions(loader)` directly and
/// needs none of this.
class DeferredLogSessions extends LogSessionSource {
  const DeferredLogSessions();

  LogSessionSource? get _delegate {
    final loader = logSessions;
    return loader == null ? null : DevtrayFileSessions(loader);
  }

  @override
  Future<List<LogSessionInfo>> list() async => await _delegate?.list() ?? const [];

  @override
  Future<List<LogEntry>> load(LogSessionInfo session) async => await _delegate?.load(session) ?? const [];

  @override
  bool get canDelete => true;

  @override
  Future<void> delete(LogSessionInfo session) async => _delegate?.delete(session);

  @override
  Future<void> deleteAll() async => _delegate?.deleteAll();
}

/// Stands in for "send the logs to my server".
///
/// Prints instead of uploading, on purpose — an example that POSTs to a real
/// endpoint is one nobody can run. The shape is the point: a sink is just
/// `write(batch)`, so a real one swaps the print for `dio.post(...)` and
/// everything else — batching, the flush policy, failure handling — already
/// applies.
///
/// Note what ISN'T here: no endpoint, auth, retry or consent logic. Those are
/// the app's decisions, which is exactly why the package ships the interface
/// and not an uploader.
class UploadLogSink extends LogSink {
  @override
  String get name => 'Upload (simulated)';

  /// Batches this sink has "sent" — read by the debug screen so the example can
  /// show that fan-out to multiple sinks is really happening.
  static int batchesSent = 0;
  static int entriesSent = 0;

  @override
  Future<void> write(List<LogEntry> batch) async {
    // A real implementation:
    //   await dio.post('/logs', data: {'lines': batch.map(formatLogEntryAsJson).toList()});
    batchesSent++;
    entriesSent += batch.length;

    // Deliberately NOT logging here. A sink that logs re-enters the store it is
    // draining — with an immediate policy that recurses until the stack gives
    // out. See the LogSink docs.
  }
}
