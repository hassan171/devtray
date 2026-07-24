import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/devtray_facade.dart';
import '../logs/devtray_export.dart';
import '../logs/devtray_log.dart';
import 'devtray_net.dart';

/// A destination for captured requests — a file, an upload, your own store.
///
/// The network counterpart to [LogSink], and deliberately the same shape: the
/// batching, the flush policy and the failure handling are identical problems,
/// so they are solved once and reused.
///
/// ```dart
/// class UploadRequests extends NetworkSink {
///   @override
///   String get name => 'Upload';
///
///   @override
///   Future<void> write(List<NetworkLogEntry> batch) async {
///     await dio.post('/requests', data: {'requests': [for (final e in batch) e.toJson()]});
///   }
/// }
/// ```
abstract class NetworkSink {
  const NetworkSink();

  /// A name for this sink, shown in the UI and in error messages.
  String get name;

  /// Persist a batch, oldest first.
  Future<void> write(List<NetworkLogEntry> batch);

  /// Release anything held open.
  Future<void> close() async {}
}

/// Sends captured requests to the sinks you add.
///
/// ## When a request is written
///
/// **On completion**, not on start. A request is mutable until it finishes —
/// the status, the body and the duration all arrive with the response — so
/// writing it early would mean either two records per request or a record
/// missing the half you wanted.
///
/// That leaves one gap: a request that never completes is never written, and an
/// app killed mid-flight or a request that hung are exactly the ones worth
/// keeping. So anything still in flight is also written when the app is
/// **backgrounded** — the last moment the OS reliably gives you — marked with
/// the pending status it actually had.
class DevtrayNetExport {
  DevtrayNetExport._() {
    Devtray.addDisableListener(() {
      _pending.clear();
      _written.clear();
    });
  }
  static final DevtrayNetExport instance = DevtrayNetExport._();

  final List<NetworkSink> _sinks = [];
  List<NetworkSink> get sinks => List.unmodifiable(_sinks);

  /// When batches are handed to the sinks. Shares [FlushPolicy] with the log
  /// exporter, because the trade-off is identical.
  FlushPolicy policy = const FlushPolicy.batched();

  /// Write still-pending requests when the app is backgrounded.
  ///
  /// On by default, and it is what makes writing-on-completion safe: without
  /// it, a request in flight when the process dies leaves no trace at all.
  bool flushOnPause = true;

  final List<NetworkLogEntry> _pending = [];
  Timer? _timer;

  /// Ids already handed to the sinks, so a request written while pending is not
  /// written again when it completes.
  final Set<int> _written = {};

  final Map<String, Object> _failed = {};

  /// Sinks disabled after throwing, and what they threw.
  Map<String, Object> get failedSinks => Map.unmodifiable(_failed);

  /// Re-enables a sink that was disabled for failing.
  void retrySink(String name) => _failed.remove(name);

  void addSink(NetworkSink sink) {
    _sinks.add(sink);
    _failed.remove(sink.name);
  }

  Future<void> removeSink(NetworkSink sink) async {
    _sinks.remove(sink);
    _failed.remove(sink.name);
    await sink.close();
  }

  /// Queues a finished request. Called by [DevtrayNet.complete].
  void ingest(NetworkLogEntry entry) {
    // No sinks means no buffer — otherwise an app that never configured export
    // would accumulate entries forever waiting for a flush with nowhere to go.
    if (_sinks.isEmpty || !Devtray.enabled) return;
    if (!_written.add(entry.id)) return;

    _pending.add(entry);
    _schedule();
  }

  /// Queues everything still in flight, for the backgrounding case.
  void flushPending() {
    if (_sinks.isEmpty || !Devtray.enabled || !flushOnPause) return;

    for (final entry in DevtrayNet.instance.entries) {
      if (entry.status != NetworkLogStatus.pending) continue;
      if (!_written.add(entry.id)) continue;
      _pending.add(entry);
    }
  }

  void _schedule() {
    switch (policy) {
      case ImmediateFlush():
        // Deferred by a microtask, matching the log exporter: `ingest` runs
        // inside `complete`, which a transport interceptor may call during any
        // phase of the frame, and starting async I/O synchronously from there is
        // the hazard CoalescingValueNotifier exists to avoid.
        scheduleMicrotask(flush);

      case BatchedFlush(:final size, :final interval):
        if (_pending.length >= size) {
          scheduleMicrotask(flush);
        } else {
          // One timer per batch window, started by the first pending entry —
          // not restarted per entry, or a steady stream of requests would push
          // the deadline back forever and never flush.
          _timer ??= Timer(interval, flush);
        }

      case ManualFlush():
        break;
    }
  }

  /// Hands everything buffered to every healthy sink.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;

    final batch = List<NetworkLogEntry>.from(_pending);
    _pending.clear();

    for (final sink in _sinks) {
      if (_failed.containsKey(sink.name)) continue;
      try {
        await sink.write(batch);
      } catch (e) {
        // Disabled rather than retried forever, and reported into the log where
        // you will actually see it — a debug tool must not take down the app it
        // exists to observe.
        _failed[sink.name] = e;
        DevtrayLog.instance.log(
          'Network sink "${sink.name}" failed and was disabled: $e',
          level: LogLevel.error,
          tag: 'devtray',
        );
      }
    }
  }

  @visibleForTesting
  Future<void> dispose() async {
    await flush();
    for (final sink in _sinks) {
      await sink.close();
    }
    _sinks.clear();
    _failed.clear();
    _written.clear();
    _timer?.cancel();
    _timer = null;
  }
}

/// One saved run of requests, as the picker shows it.
///
/// Mirrors [LogSessionInfo] — same shape, separate type, because a run's
/// requests and its log lines are separate files and a picker that mixed them
/// would offer sessions it could only half open.
class NetworkSessionInfo implements DevtraySessionInfo {
  /// Opaque to the page — handed back to [NetworkSessionSource.load] unchanged.
  final String id;

  @override
  final String label;

  @override
  final String? detail;

  @override
  final DateTime? recordedAt;

  const NetworkSessionInfo({required this.id, required this.label, this.detail, this.recordedAt});
}

/// Supplies past runs of captured requests.
///
/// The seam that lets a page browse saved requests without the core knowing
/// what a file is — `devtray_log_file` supplies the file-backed implementation,
/// and anything that can list and parse sessions fits.
abstract class NetworkSessionSource implements DevtraySessionSource<NetworkSessionInfo> {
  const NetworkSessionSource();

  /// Available sessions, newest first.
  @override
  Future<List<NetworkSessionInfo>> list();

  /// That session's requests, newest first — matching [DevtrayNet.entries], so
  /// a page renders either without knowing which it has.
  Future<List<NetworkLogEntry>> load(NetworkSessionInfo session);

  /// Whether [delete] does anything. False hides the delete controls.
  @override
  bool get canDelete => false;

  @override
  Future<void> delete(NetworkSessionInfo session) async {}

  /// Removes every session. Only offered when [canDelete].
  ///
  /// Defaults to doing nothing, so a read-only source needs no boilerplate —
  /// but a source that sets [canDelete] must override this as well as [delete],
  /// or the picker's "delete all" button does nothing at all.
  @override
  Future<void> deleteAll() async {}
}
