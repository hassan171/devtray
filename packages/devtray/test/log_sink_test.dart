import 'package:devtray/devtray.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what it was given, so a test can assert on batching and ordering.
class _RecordingSink extends LogSink {
  @override
  final String name;

  final List<List<LogEntry>> batches = [];
  int closeCount = 0;

  _RecordingSink([this.name = 'recording']);

  List<LogEntry> get allEntries => [for (final b in batches) ...b];

  @override
  Future<void> write(List<LogEntry> batch) async => batches.add(List.of(batch));

  @override
  Future<void> close() async => closeCount++;
}

class _ThrowingSink extends LogSink {
  @override
  String get name => 'throwing';

  int writeCount = 0;

  @override
  Future<void> write(List<LogEntry> batch) async {
    writeCount++;
    throw StateError('disk full');
  }
}

void main() {
  final exporter = LogExporter.instance;

  setUp(() async {
    await exporter.dispose();
    exporter.policy = const FlushPolicy.batched();
    LogStore.instance.clear();
  });

  tearDown(() async {
    await exporter.dispose();
    exporter.policy = const FlushPolicy.batched();
  });

  group('LogExporter', () {
    test('does nothing at all until a sink is added', () async {
      LogStore.instance.log('before any sink');
      await exporter.flush();

      // The important half: no sink means no pending buffer. Otherwise an app
      // that never configured export would accumulate entries forever.
      expect(exporter.pendingCount, 0);
    });

    test('a manual policy writes only when asked, and writes oldest first', () async {
      final sink = _RecordingSink();
      exporter
        ..policy = const FlushPolicy.manual()
        ..addSink(sink);

      LogStore.instance.log('first');
      LogStore.instance.log('second');
      LogStore.instance.log('third');

      expect(sink.batches, isEmpty, reason: 'manual means manual');
      expect(exporter.pendingCount, 3);

      await exporter.flush();

      expect(sink.batches.length, 1, reason: 'one flush, one batch');
      expect(
        sink.allEntries.map((e) => e.message),
        ['first', 'second', 'third'],
        reason: 'chronological — a log file should read forwards in time, '
            'which is the opposite of LogStore.entries',
      );
    });

    test('a batched policy flushes once the size threshold is crossed', () async {
      final sink = _RecordingSink();
      exporter
        ..policy = const FlushPolicy.batched(size: 3, interval: Duration(hours: 1))
        ..addSink(sink);

      LogStore.instance.log('a');
      LogStore.instance.log('b');
      await Future<void>.delayed(Duration.zero);
      expect(sink.batches, isEmpty, reason: 'still under the threshold');

      LogStore.instance.log('c');
      await Future<void>.delayed(Duration.zero);

      expect(sink.allEntries.map((e) => e.message), ['a', 'b', 'c']);
    });

    test('a batched policy flushes on the interval when the size is never reached', () {
      fakeAsync((async) {
        final sink = _RecordingSink();
        exporter
          ..policy = const FlushPolicy.batched(size: 1000, interval: Duration(seconds: 5))
          ..addSink(sink);

        LogStore.instance.log('lonely');
        async.elapse(const Duration(seconds: 4));
        expect(sink.batches, isEmpty);

        async.elapse(const Duration(seconds: 2));
        expect(sink.allEntries.single.message, 'lonely');
      });
    });

    test('a steady stream still flushes — the timer is not restarted per entry', () {
      fakeAsync((async) {
        final sink = _RecordingSink();
        exporter
          ..policy = const FlushPolicy.batched(size: 1000, interval: Duration(seconds: 5))
          ..addSink(sink);

        // One line every second, forever. If the interval timer were reset on
        // each entry the deadline would keep moving and nothing would ever be
        // written.
        for (var i = 0; i < 8; i++) {
          LogStore.instance.log('tick $i');
          async.elapse(const Duration(seconds: 1));
        }

        expect(sink.batches, isNotEmpty, reason: 'a continuous stream must still reach the sink');
      });
    });

    test('an immediate policy writes without waiting for a threshold', () async {
      final sink = _RecordingSink();
      exporter
        ..policy = const FlushPolicy.immediate()
        ..addSink(sink);

      LogStore.instance.log('now');
      // Deferred by a microtask on purpose — ingest can be called mid-build.
      await Future<void>.delayed(Duration.zero);

      expect(sink.allEntries.single.message, 'now');
    });

    test('a sink that throws is disabled, and does not stop the others', () async {
      final bad = _ThrowingSink();
      final good = _RecordingSink();
      exporter
        ..policy = const FlushPolicy.manual()
        ..addSink(bad)
        ..addSink(good);

      LogStore.instance.log('one');
      await exporter.flush();

      expect(good.allEntries.map((e) => e.message), contains('one'), reason: 'the healthy sink still got it');
      expect(exporter.failedSinks.keys, contains('throwing'));

      LogStore.instance.log('two');
      await exporter.flush();

      expect(bad.writeCount, 1, reason: 'a failed sink is not called again');
    });

    test('a failing sink reports itself into the log, where it is visible', () async {
      exporter
        ..policy = const FlushPolicy.manual()
        ..addSink(_ThrowingSink());

      LogStore.instance.log('trigger');
      await exporter.flush();

      final reported = LogStore.instance.entries.where((e) => e.tag == 'devtray');
      expect(reported, isNotEmpty, reason: 'a silently broken sink is worse than a noisy one');
      expect(reported.first.message, contains('disk full'));
    });

    test('retrySink re-enables a disabled sink', () async {
      final bad = _ThrowingSink();
      exporter
        ..policy = const FlushPolicy.manual()
        ..addSink(bad);

      LogStore.instance.log('one');
      await exporter.flush();
      expect(exporter.failedSinks, isNotEmpty);

      exporter.retrySink('throwing');
      expect(exporter.failedSinks, isEmpty);

      LogStore.instance.log('two');
      await exporter.flush();
      expect(bad.writeCount, 2, reason: 'called again after the retry');
    });

    test('entries logged during a flush land in the next batch, not the void', () async {
      final sink = _RecordingSink();
      exporter
        ..policy = const FlushPolicy.manual()
        ..addSink(sink);

      LogStore.instance.log('first');

      // Two flushes racing: the second must not clear the batch the first is
      // still writing.
      await Future.wait([exporter.flush(), exporter.flush()]);

      expect(sink.allEntries.where((e) => e.message == 'first').length, 1, reason: 'written exactly once');
    });

    test('removing a sink closes it', () async {
      final sink = _RecordingSink();
      exporter.addSink(sink);
      await exporter.removeSink(sink);

      expect(sink.closeCount, 1);
      expect(exporter.sinks, isEmpty);
    });

    test('the kill switch stops export dead', () async {
      final sink = _RecordingSink();
      exporter
        ..policy = const FlushPolicy.manual()
        ..addSink(sink);

      DevtrayKillSwitch.enabled = false;
      addTearDown(() => DevtrayKillSwitch.enabled = true);

      LogStore.instance.log('should not be persisted');
      await exporter.flush();

      expect(sink.batches, isEmpty, reason: 'a disabled overlay must not write logs to disk');
    });
  });

  group('the JSON-Lines format', () {
    test('round-trips an ordinary entry', () {
      LogStore.instance.log('hello', level: LogLevel.warning, tag: 'auth');
      final original = LogStore.instance.entries.single;

      final parsed = parseLogEntries(formatLogEntryAsJson(original)).single;

      expect(parsed.message, 'hello');
      expect(parsed.level, LogLevel.warning);
      expect(parsed.tag, 'auth');
      expect(parsed.time.toIso8601String(), original.time.toIso8601String());
    });

    test('round-trips an error entry, keeping what makes it an error', () {
      LogStore.instance.report(
        StateError('boom'),
        stackTrace: StackTrace.current,
        context: 'while testing',
        library: 'devtray',
      );
      final original = LogStore.instance.entries.first;

      final parsed = parseLogEntries(formatLogEntryAsJson(original)).single;

      expect(parsed.isError, isTrue, reason: 'source is what distinguishes an error from a log line');
      expect(parsed.source, ErrorSource.reported);
      expect(parsed.errorContext, 'while testing');
      expect(parsed.library, 'devtray');
      expect(parsed.error.toString(), contains('boom'));
      expect(parsed.stackTrace, isNotNull);
    });

    test('parses newest-first, matching LogStore.entries', () {
      final text = [
        for (final m in ['oldest', 'middle', 'newest'])
          formatLogEntryAsJson(
            LogEntry(id: 0, time: DateTime(2026, 1, 1), level: LogLevel.debug, message: m),
          ),
      ].join('\n');

      final parsed = parseLogEntries(text);

      expect(
        parsed.map((e) => e.message),
        ['newest', 'middle', 'oldest'],
        reason: 'so the same page can render a loaded file without knowing it is one',
      );
    });

    test('a damaged line costs that line, not the file', () {
      final good = formatLogEntryAsJson(
        LogEntry(id: 1, time: DateTime(2026, 1, 1), level: LogLevel.info, message: 'survivor'),
      );

      // The realistic shape of a crash: a file cut off mid-write.
      final text = '$good\n{"id": 2, "message": "truncated hal';

      final parsed = parseLogEntries(text);

      expect(parsed.length, 1);
      expect(parsed.single.message, 'survivor');
    });

    test('ignores blank lines and non-object lines', () {
      final good = formatLogEntryAsJson(
        LogEntry(id: 1, time: DateTime(2026, 1, 1), level: LogLevel.info, message: 'kept'),
      );

      expect(parseLogEntries('\n\n$good\n[1,2,3]\n\n').single.message, 'kept');
    });

    test('the text format is human-readable and includes the error', () {
      final line = formatLogEntryAsText(
        LogEntry(
          id: 1,
          time: DateTime.utc(2026, 7, 19, 14, 30),
          level: LogLevel.error,
          message: 'request failed',
          tag: 'net',
          error: StateError('timeout'),
        ),
      );

      expect(line, contains('2026-07-19T14:30'));
      expect(line, contains('ERROR'));
      expect(line, contains('[net]'));
      expect(line, contains('request failed'));
      expect(line, contains('timeout'));
    });
  });
}
