import 'dart:io';

import 'package:devtray/devtray.dart';
import 'package:devtray_log_file/devtray_log_file.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkLogEntry _entry({int id = 1, String path = '/orders', int? code = 200}) {
  final entry = NetworkLogEntry(
    id: id,
    method: 'GET',
    uri: Uri.parse('https://api.test$path'),
    requestHeaders: const {'accept': 'application/json'},
    queryParameters: const {},
    requestBody: null,
    startedAt: DateTime(2026, 7, 22, 14, 30),
    fields: const {'screen': 'checkout'},
  );
  if (code != null) {
    entry
      ..statusCode = code
      ..status = NetworkLogStatus.success
      ..completedAt = DateTime(2026, 7, 22, 14, 30, 1)
      ..responseBody = '{"ok":true}';
  }
  return entry;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('devtray_net_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('writes requests as JSON lines and reads them back', () async {
    final sink = await FileNetworkSink.open(directory: dir);
    await sink.write([_entry(id: 1), _entry(id: 2, path: '/users')]);

    final parsed = parseNetworkEntries(await sink.file.readAsString());

    expect(parsed, hasLength(2));
    expect(parsed.first.uri.path, '/orders');
    expect(parsed.first.statusCode, 200);
    expect(parsed.first.responseBody, '{"ok":true}');
    // The context the request was made under survives the trip.
    expect(parsed.first.fields['screen'], 'checkout');
    expect(parsed.last.uri.path, '/users');
  });

  test('a request still in flight is written as pending', () async {
    final sink = await FileNetworkSink.open(directory: dir);
    await sink.write([_entry(code: null)]);

    final parsed = parseNetworkEntries(await sink.file.readAsString());

    // The backgrounded-mid-flight case: recorded as what it actually was.
    expect(parsed.single.status, NetworkLogStatus.pending);
    expect(parsed.single.completedAt, isNull);
  });

  test('a damaged line is skipped, not fatal', () async {
    final sink = await FileNetworkSink.open(directory: dir);
    await sink.write([_entry(id: 1)]);
    // A crash mid-write leaves exactly this.
    await sink.file.writeAsString('{"id":2,"method":"GE', mode: FileMode.append);

    final parsed = parseNetworkEntries(await sink.file.readAsString());

    // The runs worth reading are often the ones the app died halfway through.
    expect(parsed, hasLength(1));
    expect(parsed.single.id, 1);
  });

  test('uses its own extension, so the log loader cannot pick it up', () async {
    // Files are created on first write, not on open.
    await (await FileNetworkSink.open(directory: dir)).write([_entry()]);
    await (await FileLogSink.open(directory: dir)).write([LogEntry(id: 1, time: DateTime(2026), level: LogLevel.debug, message: 'x')]);

    final requests = await FileNetworkSink.listRequestFiles(dir);
    expect(requests, hasLength(1));
    expect(requests.single.path, endsWith('.devtraynet'));
    expect(requests.single.uri.pathSegments.last, startsWith('requests_'));
  });

  test('rotates past maxBytes, keeping the session stamp', () async {
    final sink = await FileNetworkSink.open(directory: dir, maxBytes: 200);

    for (var i = 0; i < 12; i++) {
      await sink.write([_entry(id: i, path: '/a-fairly-long-path-to-fill-the-file/$i')]);
    }

    final files = await FileNetworkSink.listRequestFiles(dir);
    expect(files.length, greaterThan(1), reason: 'should have rolled over');

    // Continuations keep the run's start stamp, so every part of one run sorts
    // together and prunes together.
    final stamps = files.map((f) {
      final base = f.uri.pathSegments.last.replaceAll('.devtraynet', '').replaceFirst('requests_', '');
      final part = base.indexOf('_part');
      return part == -1 ? base : base.substring(0, part);
    }).toSet();
    expect(stamps, hasLength(1));
  });

  test('prunes whole sessions past maxFiles', () async {
    // Four prior runs, each of which actually wrote — an unwritten session
    // leaves no file, and the test would pass without pruning anything.
    for (var i = 0; i < 4; i++) {
      await (await FileNetworkSink.open(directory: dir)).write([_entry(id: i)]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await FileNetworkSink.listRequestFiles(dir), hasLength(4));

    // Opening with a cap prunes on the way in.
    await (await FileNetworkSink.open(directory: dir, maxFiles: 2)).write([_entry(id: 99)]);

    final files = await FileNetworkSink.listRequestFiles(dir);
    // Two kept plus the new run: pruning happens on open, before this session
    // has written anything, so the cap bounds PRIOR sessions.
    expect(files, hasLength(3), reason: 'oldest sessions evicted whole');
  });
}
