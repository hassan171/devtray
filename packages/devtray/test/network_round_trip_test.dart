import 'dart:convert';

import 'package:devtray/devtray.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkLogEntry _completed({int status = 500, String? error}) {
  final entry = DevtrayNet.instance.add(
    method: 'POST',
    uri: Uri.parse('https://api.test/orders?dry=1'),
    requestHeaders: {'authorization': 'Bearer x', 'content-type': 'application/json'},
    queryParameters: {'dry': '1'},
    requestBody: '{"item":42}',
  )!;
  DevtrayNet.instance.complete(
    entry.id,
    status: error == null ? NetworkLogStatus.success : NetworkLogStatus.failed,
    statusCode: status,
    responseHeaders: {'content-type': ['application/json']},
    responseBody: '{"error":"nope"}',
    errorMessage: error,
  );
  return entry;
}

void main() {
  setUp(() {
    Devtray.reset();
    DevtrayLog.instance
      ..clear()
      ..clearContext()
      ..clearEnrichers();
    DevtrayNet.instance
      ..clear()
      ..excludedUrlPatterns.clear();
  });

  group('NetworkLogEntry JSON', () {
    test('survives a round trip through actual JSON', () {
      Devtray.setContext('screen', 'checkout');
      final original = _completed();

      // Through a real encode/decode, not just the maps: a value that only
      // looks encodable is the whole failure mode this guards.
      final decoded = NetworkLogEntry.fromJson(
        Map<String, Object?>.from(jsonDecode(jsonEncode(original.toJson())) as Map),
      );

      expect(decoded.id, original.id);
      expect(decoded.method, 'POST');
      expect(decoded.uri, original.uri);
      expect(decoded.statusCode, 500);
      expect(decoded.status, NetworkLogStatus.success);
      expect(decoded.requestHeaders['authorization'], 'Bearer x');
      expect(decoded.responseHeaders['content-type'], ['application/json']);
      expect(decoded.responseBody, '{"error":"nope"}');
      expect(decoded.completedAt, isNotNull);
      expect(decoded.duration, isNotNull);
      // The context the request was made under is part of the record.
      expect(decoded.fields['screen'], 'checkout');
    });

    test('a request still in flight reads back as pending', () {
      final pending = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/slow'))!;

      final decoded = NetworkLogEntry.fromJson(
        Map<String, Object?>.from(jsonDecode(jsonEncode(pending.toJson())) as Map),
      );

      expect(decoded.status, NetworkLogStatus.pending);
      expect(decoded.completedAt, isNull);
    });

    test('a truncated record still yields the request', () {
      // A file crash-truncated mid-write, or one from an older version. Losing
      // the record entirely to a missing key would throw away the very run you
      // saved the session to look at.
      final decoded = NetworkLogEntry.fromJson({'method': 'GET', 'uri': 'https://api.test/x'});

      expect(decoded.method, 'GET');
      expect(decoded.uri.host, 'api.test');
      expect(decoded.status, NetworkLogStatus.pending);
    });

    test('an unencodable body is rendered rather than failing the record', () {
      final entry = DevtrayNet.instance.add(
        method: 'POST',
        uri: Uri.parse('https://api.test/x'),
        requestBody: Object(),
      )!;

      // One un-encodable value must not cost the whole request.
      expect(() => jsonEncode(entry.toJson()), returnsNormally);
    });
  });

  group('NetworkError through a saved session', () {
    test('keeps the request, so the detail pane renders it as a real one', () {
      final failed = _completed(error: 'Connection reset');
      DevtrayLog.instance.report(NetworkError(failed), source: ErrorSource.network);

      final line = jsonEncode(jsonDecode(formatLogEntryAsJson(DevtrayLog.instance.entries.first)));
      final parsed = parseLogEntries(line).single;

      // This is the bug: the error was flattened to its one-line toString(), so
      // `case final NetworkError n` in the detail pane could never match a
      // loaded session and every network error read back as a bare string.
      expect(parsed.error, isA<NetworkError>());

      final entry = (parsed.error as NetworkError).entry;
      expect(entry.method, 'POST');
      expect(entry.statusCode, 500);
      expect(entry.errorMessage, 'Connection reset');
      expect(entry.responseBody, '{"error":"nope"}');
    });

    test('an ordinary error is still a plain string', () {
      DevtrayLog.instance.report(StateError('boom'));

      final line = formatLogEntryAsJson(DevtrayLog.instance.entries.first);
      final parsed = parseLogEntries(line).single;

      // Only NetworkError is worth keeping whole — anything else is not
      // serialisable in general, and by read-back time its type may not even be
      // in scope.
      expect(parsed.error, isA<String>());
      expect(parsed.error, contains('boom'));
    });
  });
}
