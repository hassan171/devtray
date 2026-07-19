import 'dart:io';

import 'package:devtray/devtray.dart';
import 'package:devtray_log_file/devtray_log_file.dart';
import 'package:flutter_test/flutter_test.dart';

LogEntry _entry(String message, {int id = 0, LogLevel level = LogLevel.debug, String? tag}) =>
    LogEntry(id: id, time: DateTime(2026, 7, 19, 14, 30), level: level, message: message, tag: tag);

void main() {
  late Directory dir;

  setUp(() async {
    // A real directory rather than a mock: the things worth testing here are
    // rotation, pruning and round-tripping, and all three are about what
    // actually lands on disk.
    dir = await Directory.systemTemp.createTemp('devtray_log_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('FileLogSink', () {
    test('writes a batch as JSON lines that parse back', () async {
      final sink = await FileLogSink.open(directory: dir);

      await sink.write([_entry('first', id: 1), _entry('second', id: 2)]);

      final parsed = parseLogEntries(await sink.file.readAsString());
      expect(parsed.map((e) => e.message), ['second', 'first'], reason: 'parsed newest-first');
    });

    test('appends across batches rather than overwriting', () async {
      final sink = await FileLogSink.open(directory: dir);

      await sink.write([_entry('one', id: 1)]);
      await sink.write([_entry('two', id: 2)]);

      final parsed = parseLogEntries(await sink.file.readAsString());
      expect(parsed.length, 2, reason: 'the second write must not clobber the first');
    });

    test('a session file survives the sink being dropped mid-run', () async {
      final sink = await FileLogSink.open(directory: dir);
      await sink.write([_entry('written before the crash')]);

      // No close() — simulating the process dying. Each write flushes, so the
      // data must already be on disk.
      final parsed = parseLogEntries(await sink.file.readAsString());
      expect(parsed.single.message, 'written before the crash');
    });

    test('rotates to a new file past maxBytes', () async {
      final sink = await FileLogSink.open(directory: dir, maxBytes: 200);
      final first = sink.file;

      // Enough to cross the threshold.
      for (var i = 0; i < 10; i++) {
        await sink.write([_entry('a reasonably long log line number $i', id: i)]);
      }

      final files = await FileLogSink.listSessionFiles(dir);
      expect(files.length, greaterThan(1), reason: 'should have rolled over');
      expect(await first.exists(), isTrue, reason: 'the rolled-off file is part of the session, not garbage');
    });

    test('prunes the oldest files past maxFiles', () async {
      // Pre-existing sessions, oldest-looking name first.
      for (final stamp in ['2026-01-01T00-00-00', '2026-02-01T00-00-00', '2026-03-01T00-00-00']) {
        await File('${dir.path}${Platform.pathSeparator}session_$stamp${FileLogSink.extension}').writeAsString('{}\n');
      }

      // Opening with a cap of 2 prunes on open, then adds its own.
      await FileLogSink.open(directory: dir, maxFiles: 2);

      final remaining = await FileLogSink.listSessionFiles(dir);
      final names = remaining.map((f) => f.path).join(' ');
      expect(names, isNot(contains('2026-01-01')), reason: 'the oldest goes first');
    });

    test('ignores files that are not session logs', () async {
      await File('${dir.path}${Platform.pathSeparator}notes.txt').writeAsString('not a log');
      await FileLogSink.open(directory: dir);

      final files = await FileLogSink.listSessionFiles(dir);
      expect(files.every((f) => f.path.endsWith(FileLogSink.extension)), isTrue);
    });

    test('an empty batch writes nothing', () async {
      final sink = await FileLogSink.open(directory: dir);
      await sink.write([]);

      expect(await sink.file.exists(), isFalse, reason: 'no entries, no file');
    });

    test('honours a custom format', () async {
      final sink = await FileLogSink.open(directory: dir, format: formatLogEntryAsText);

      await sink.write([_entry('human readable', tag: 'ui')]);

      final text = await sink.file.readAsString();
      expect(text, contains('[ui]'));
      expect(text, contains('human readable'));
      expect(text, isNot(contains('"message"')), reason: 'text format, not JSON');
    });
  });

  group('LogSessionLoader', () {
    test('lists sessions newest first', () async {
      for (final stamp in ['2026-01-01T00-00-00', '2026-03-01T00-00-00', '2026-02-01T00-00-00']) {
        await File('${dir.path}${Platform.pathSeparator}session_$stamp${FileLogSink.extension}').writeAsString('{}\n');
      }

      final sessions = await LogSessionLoader(dir).list();

      expect(sessions.first.name, startsWith('2026-03-01'));
      expect(sessions.last.name, startsWith('2026-01-01'));
    });

    test('loads a session back into entries', () async {
      final sink = await FileLogSink.open(directory: dir);
      await sink.write([_entry('recovered', id: 7, level: LogLevel.warning, tag: 'boot')]);

      final loader = LogSessionLoader(dir);
      final entries = await loader.load((await loader.list()).single);

      expect(entries.single.message, 'recovered');
      expect(entries.single.level, LogLevel.warning);
      expect(entries.single.tag, 'boot');
    });

    test('a session deleted between listing and loading returns empty, not a crash', () async {
      final sink = await FileLogSink.open(directory: dir);
      await sink.write([_entry('here for now')]);

      final loader = LogSessionLoader(dir);
      final session = (await loader.list()).single;

      // The race a running sink's pruning creates.
      await File(session.path).delete();

      expect(await loader.load(session), isEmpty);
    });

    test('a truncated file loads the lines that survived', () async {
      final file = File('${dir.path}${Platform.pathSeparator}session_2026-01-01T00-00-00${FileLogSink.extension}');
      await file.writeAsString('${formatLogEntryAsJson(_entry('complete', id: 1))}\n{"id": 2, "message": "cut off mid-wri');

      final loader = LogSessionLoader(dir);
      final entries = await loader.load((await loader.list()).single);

      expect(entries.single.message, 'complete', reason: 'the file worth reading is often the one the app died writing');
    });

    test('delete removes a session', () async {
      final sink = await FileLogSink.open(directory: dir);
      await sink.write([_entry('doomed')]);

      final loader = LogSessionLoader(dir);
      await loader.delete((await loader.list()).single);

      expect(await loader.list(), isEmpty);
    });

    test('deleteAll clears everything', () async {
      for (final stamp in ['2026-01-01T00-00-00', '2026-02-01T00-00-00']) {
        await File('${dir.path}${Platform.pathSeparator}session_$stamp${FileLogSink.extension}').writeAsString('{}\n');
      }

      final loader = LogSessionLoader(dir);
      await loader.deleteAll();

      expect(await loader.list(), isEmpty);
    });

    test('listing a directory that does not exist is empty, not an error', () async {
      final missing = Directory('${dir.path}${Platform.pathSeparator}never_created');
      expect(await LogSessionLoader(missing).list(), isEmpty);
    });
  });

  group('DevtrayFileSessions', () {
    test('exposes sessions through the core interface', () async {
      final sink = await FileLogSink.open(directory: dir);
      await sink.write([_entry('through the adapter')]);

      final source = DevtrayFileSessions(LogSessionLoader(dir));
      final sessions = await source.list();

      expect(sessions, hasLength(1));
      expect(source.canDelete, isTrue);

      final entries = await source.load(sessions.single);
      expect(entries.single.message, 'through the adapter');
    });

    test('loading a session whose file vanished returns empty', () async {
      final sink = await FileLogSink.open(directory: dir);
      await sink.write([_entry('temporary')]);

      final source = DevtrayFileSessions(LogSessionLoader(dir));
      final session = (await source.list()).single;
      await File(session.id).delete();

      expect(await source.load(session), isEmpty);
    });
  });
}
