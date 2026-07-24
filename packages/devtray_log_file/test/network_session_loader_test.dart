import 'dart:io';

import 'package:devtray/devtray.dart';
import 'package:devtray_log_file/devtray_log_file.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkLogEntry _entry(int id) => NetworkLogEntry(
  id: id,
  method: 'GET',
  uri: Uri.parse('https://api.test/x/$id'),
  requestHeaders: const {},
  queryParameters: const {},
  requestBody: null,
  startedAt: DateTime(2026, 7, 22, 14, 30),
)..status = NetworkLogStatus.success;

/// Writes [runs] separate session files.
Future<void> _seed(Directory dir, int runs) async {
  for (var i = 0; i < runs; i++) {
    await (await FileNetworkSink.open(directory: dir, maxFiles: 1 << 30)).write([_entry(i)]);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory dir;
  late DevtrayFileRequestSessions source;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('devtray_net_sessions');
    source = DevtrayFileRequestSessions(NetworkSessionLoader(dir));
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('lists saved runs, newest first', () async {
    await _seed(dir, 3);

    final sessions = await source.list();

    expect(sessions, hasLength(3));
    expect(sessions.first.detail, isNotNull, reason: 'a size distinguishes one run from another');
  });

  test('loads a run back', () async {
    await _seed(dir, 1);

    final requests = await source.load((await source.list()).single);

    expect(requests, hasLength(1));
    expect(requests.single.uri.path, '/x/0');
  });

  test('deletes one session', () async {
    await _seed(dir, 3);
    final sessions = await source.list();

    await source.delete(sessions.first);

    expect(await source.list(), hasLength(2));
  });

  test('deleteAll removes every session', () async {
    await _seed(dir, 3);
    expect(await source.list(), hasLength(3));

    // The base class defaults deleteAll to a no-op so a read-only source needs
    // no boilerplate — which meant forgetting to override it here left the
    // picker's "delete all" button doing nothing at all, silently.
    await source.deleteAll();

    expect(await source.list(), isEmpty);
  });

  test('offers deletion, so the picker shows its controls', () {
    expect(source.canDelete, isTrue);
  });
}
