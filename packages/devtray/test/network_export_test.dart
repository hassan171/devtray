import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what it was handed, and can be told to fail.
class _RecordingSink extends NetworkSink {
  final List<List<NetworkLogEntry>> batches = [];
  bool throwOnWrite = false;

  @override
  String get name => 'recording';

  @override
  Future<void> write(List<NetworkLogEntry> batch) async {
    if (throwOnWrite) throw StateError('sink is broken');
    batches.add(List.of(batch));
  }

  List<NetworkLogEntry> get written => [for (final b in batches) ...b];
}

NetworkLogEntry _start([String path = '/orders']) =>
    DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test$path'))!;

void _finish(NetworkLogEntry e, {int code = 200}) => DevtrayNet.instance.complete(
      e.id,
      status: NetworkLogStatus.success,
      statusCode: code,
    );

void main() {
  late _RecordingSink sink;

  setUp(() async {
    Devtray.reset();
    DevtrayLog.instance.clear();
    DevtrayNet.instance
      ..clear()
      ..excludedUrlPatterns.clear();
    await DevtrayNetExport.instance.dispose();

    sink = _RecordingSink();
    DevtrayNetExport.instance
      ..policy = const FlushPolicy.immediate()
      ..flushOnPause = true
      ..addSink(sink);
  });

  tearDown(() => DevtrayNetExport.instance.dispose());

  group('when a request is written', () {
    test('on completion, not on start', () async {
      final entry = _start();
      await Future<void>.delayed(Duration.zero);

      // Nothing yet: the status, body and duration all arrive with the
      // response, so an early write would lose the half you wanted.
      expect(sink.written, isEmpty);

      _finish(entry);
      await Future<void>.delayed(Duration.zero);

      expect(sink.written.map((e) => e.id), [entry.id]);
      expect(sink.written.single.statusCode, 200);
    });

    test('once only, even after a pending flush', () async {
      final entry = _start();

      // Backgrounded mid-flight: written as pending.
      DevtrayNetExport.instance.flushPending();
      await DevtrayNetExport.instance.flush();
      expect(sink.written, hasLength(1));

      // …then it completes. It must not be written a second time, or the file
      // would hold two records for one request and a reader would have to
      // reconcile them.
      _finish(entry);
      await Future<void>.delayed(Duration.zero);

      expect(sink.written, hasLength(1));
    });

    test('still-pending requests are written when the app is backgrounded', () async {
      final pending = _start('/slow');
      final done = _start('/fast');
      _finish(done);
      await Future<void>.delayed(Duration.zero);

      DevtrayNetExport.instance.flushPending();
      await DevtrayNetExport.instance.flush();

      // The gap that writing-on-completion leaves: a request in flight when the
      // process dies would otherwise leave no trace, and those are exactly the
      // ones worth keeping.
      final ids = sink.written.map((e) => e.id).toList();
      expect(ids, containsAll([done.id, pending.id]));
      expect(
        sink.written.firstWhere((e) => e.id == pending.id).status,
        NetworkLogStatus.pending,
        reason: 'recorded as what it actually was',
      );
    });

    test('flushOnPause: false leaves in-flight requests alone', () async {
      DevtrayNetExport.instance.flushOnPause = false;
      _start('/slow');

      DevtrayNetExport.instance.flushPending();
      await DevtrayNetExport.instance.flush();

      expect(sink.written, isEmpty);
    });
  });

  group('safety', () {
    test('nothing is buffered when no sink is configured', () async {
      await DevtrayNetExport.instance.dispose();

      final entry = _start();
      _finish(entry);
      await Future<void>.delayed(Duration.zero);

      // An app that never configured export must not accumulate entries
      // forever waiting for a flush that has nowhere to go.
      expect(DevtrayNetExport.instance.sinks, isEmpty);
    });

    test('nothing is written while capture is off', () async {
      Devtray.enabled = false;
      addTearDown(Devtray.reset);

      final entry = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/x'));
      expect(entry, isNull, reason: 'the store refuses it first');
      expect(sink.written, isEmpty);
    });

    test('a throwing sink is disabled and reported, not retried forever', () async {
      sink.throwOnWrite = true;

      final entry = _start();
      _finish(entry);
      await Future<void>.delayed(Duration.zero);

      expect(DevtrayNetExport.instance.failedSinks.keys, contains('recording'));
      expect(
        DevtrayLog.instance.entries.any((e) => e.message.contains('was disabled')),
        isTrue,
        reason: 'a broken sink must be visible, not silent',
      );

      // And it stays disabled rather than throwing on every request after.
      sink.throwOnWrite = false;
      final second = _start('/again');
      _finish(second);
      await Future<void>.delayed(Duration.zero);
      expect(sink.written, isEmpty);

      DevtrayNetExport.instance.retrySink('recording');
      final third = _start('/third');
      _finish(third);
      await Future<void>.delayed(Duration.zero);
      expect(sink.written, hasLength(1));
    });
  });

  group('batching', () {
    test('a batched policy waits for the batch', () async {
      DevtrayNetExport.instance.policy = const FlushPolicy.batched(size: 3, interval: Duration(hours: 1));

      for (final path in ['/a', '/b']) {
        _finish(_start(path));
      }
      await Future<void>.delayed(Duration.zero);
      expect(sink.written, isEmpty, reason: 'two of three');

      _finish(_start('/c'));
      await Future<void>.delayed(Duration.zero);
      expect(sink.written, hasLength(3));
    });

    test('manual writes nothing until you ask', () async {
      DevtrayNetExport.instance.policy = const FlushPolicy.manual();

      _finish(_start());
      await Future<void>.delayed(Duration.zero);
      expect(sink.written, isEmpty);

      await DevtrayNetExport.instance.flush();
      expect(sink.written, hasLength(1));
    });
  });

  group('configure', () {
    testWidgets('networkTo registers a sink', (tester) async {
      await DevtrayNetExport.instance.dispose();
      final mine = _RecordingSink();

      final original = debugPrint;
      try {
        runDebugApp(
          () => const SizedBox.shrink(),
          configure: (d) => d..networkTo(mine),
        );
        await tester.pumpAndSettle();

        expect(DevtrayNetExport.instance.sinks, contains(mine));
      } finally {
        stopCapturingDebugPrint();
        debugPrint = original;
      }
    });
  });
}
