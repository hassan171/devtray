import 'dart:convert';
import 'dart:typed_data';

import 'package:debug_overlay/debug_overlay.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// A dio adapter that fails loudly if anything actually reaches "the network".
/// Every mocked request must be short-circuited before this is hit.
class _ExplodingDioAdapter implements HttpClientAdapter {
  bool wasCalled = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    wasCalled = true;
    return ResponseBody.fromString('{"real": true}', 200, headers: {
      'content-type': ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// A dio adapter that returns a fixed status — for testing how the real network
/// path is classified, with no mocking in play.
class _StatusDioAdapter implements HttpClientAdapter {
  final int statusCode;
  _StatusDioAdapter(this.statusCode);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString('{"ok": true}', statusCode, headers: {
      'content-type': ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Same idea for package:http.
class _ExplodingHttpClient extends http.BaseClient {
  bool wasCalled = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    wasCalled = true;
    return http.StreamedResponse(Stream.value(utf8.encode('{"real": true}')), 200);
  }
}

void main() {
  late MockStore mocks;
  late NetworkLogStore logs;

  setUp(() {
    // Fresh singletons per test.
    mocks = MockStore.instance
      ..enable()
      ..clear()
      ..offline.value = false
      ..rulesEnabled.value = true;
    logs = NetworkLogStore.instance..clear();
    LogStore.instance.clear();
  });

  group('MockRule.matches', () {
    test('substring matching on the URL', () {
      const rule = MockRule(id: 'r', urlPattern: '/orders');

      expect(rule.matches(url: 'https://api.test/v1/orders', method: 'GET'), isTrue);
      expect(rule.matches(url: 'https://api.test/v1/users', method: 'GET'), isFalse);
    });

    test('regex matching when opted in', () {
      const rule = MockRule(id: 'r', urlPattern: r'/users/\d+/orders$', isRegex: true);

      expect(rule.matches(url: 'https://api.test/users/42/orders', method: 'GET'), isTrue);
      expect(rule.matches(url: 'https://api.test/users/me/orders', method: 'GET'), isFalse);
    });

    test('an invalid regex never matches, rather than throwing', () {
      // A half-typed pattern in the editor must not blow up every request.
      const rule = MockRule(id: 'r', urlPattern: '[unclosed', isRegex: true);
      expect(rule.matches(url: 'https://api.test/x', method: 'GET'), isFalse);
    });

    test('method filter', () {
      const rule = MockRule(id: 'r', urlPattern: '/orders', method: 'POST');

      expect(rule.matches(url: 'https://api.test/orders', method: 'POST'), isTrue);
      expect(rule.matches(url: 'https://api.test/orders', method: 'GET'), isFalse);
    });

    test('a disabled rule never matches', () {
      const rule = MockRule(id: 'r', urlPattern: '/orders', enabled: false);
      expect(rule.matches(url: 'https://api.test/orders', method: 'GET'), isFalse);
    });

    test('an empty pattern matches nothing — not everything', () {
      // A blank field in the editor must not silently mock the whole app.
      const rule = MockRule(id: 'r', urlPattern: '');
      expect(rule.matches(url: 'https://api.test/anything', method: 'GET'), isFalse);
    });
  });

  group('decideMock', () {
    test('no rules → pass through', () {
      expect(decideMock(url: 'https://api.test/x', method: 'GET'), isA<PassThrough>());
    });

    test('offline beats everything', () {
      mocks
        ..add(const MockRule(id: 'r', urlPattern: '/x', statusCode: 200))
        ..offline.value = true;

      expect(decideMock(url: 'https://api.test/x', method: 'GET'), isA<FailWith>());
    });

    test('rulesEnabled=false parks the rules without deleting them', () {
      mocks
        ..add(const MockRule(id: 'r', urlPattern: '/x', statusCode: 500))
        ..rulesEnabled.value = false;

      expect(decideMock(url: 'https://api.test/x', method: 'GET'), isA<PassThrough>());
      expect(mocks.rules.value, hasLength(1)); // still there
    });

    test('first matching rule wins — order matters', () {
      mocks
        ..add(const MockRule(id: 'specific', urlPattern: '/orders/42', statusCode: 418))
        ..add(const MockRule(id: 'broad', urlPattern: '/orders', statusCode: 500));

      final d = decideMock(url: 'https://api.test/orders/42', method: 'GET');
      expect((d as RespondWith).statusCode, 418);
    });

    test('each action maps to the right decision', () {
      mocks.add(const MockRule(id: 'f', urlPattern: '/fail', action: MockAction.fail));
      expect(decideMock(url: 'https://api.test/fail', method: 'GET'), isA<FailWith>());

      mocks.clear();
      mocks.add(const MockRule(id: 'd', urlPattern: '/slow', action: MockAction.delayOnly, delay: Duration(seconds: 1)));
      final d = decideMock(url: 'https://api.test/slow', method: 'GET');
      expect(d, isA<PassThrough>());
      expect((d as PassThrough).delay, const Duration(seconds: 1));
    });
  });

  group('MockRule.decodedBody', () {
    test('parses JSON', () {
      const rule = MockRule(id: 'r', urlPattern: '/x', body: '{"a": 1}');
      expect(rule.decodedBody, {'a': 1});
    });

    test('falls back to the raw string when it is not JSON', () {
      const rule = MockRule(id: 'r', urlPattern: '/x', body: 'plain text');
      expect(rule.decodedBody, 'plain text');
    });

    test('empty body is null', () {
      expect(const MockRule(id: 'r', urlPattern: '/x').decodedBody, isNull);
    });
  });

  group('dio adapter', () {
    late Dio dio;
    late _ExplodingDioAdapter network;

    setUp(() {
      network = _ExplodingDioAdapter();
      dio = Dio()
        ..httpClientAdapter = network
        ..interceptors.add(DebugDioInterceptor());
    });

    test('a respond rule fakes the response WITHOUT contacting the server', () async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders', statusCode: 500, body: '{"message":"boom"}'));

      final res = await dio.get<dynamic>('https://api.test/orders', options: Options(validateStatus: (_) => true));

      expect(res.statusCode, 500);
      expect(res.data, {'message': 'boom'});
      expect(network.wasCalled, isFalse, reason: 'the real server must never be hit');
    });

    test('a mocked response is badged in the log', () async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders', statusCode: 500));

      await dio.get<dynamic>('https://api.test/orders', options: Options(validateStatus: (_) => true));

      final entry = logs.entries.single;
      expect(entry.extras.keys, contains(kMockedExtraLabel));
      expect(entry.extras[kMockedExtraLabel], contains('never contacted'));
    });

    test('a fail rule throws a connection error and never hits the server', () async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders', action: MockAction.fail));

      await expectLater(
        dio.get<dynamic>('https://api.test/orders'),
        throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.connectionError)),
      );
      expect(network.wasCalled, isFalse);
    });

    test('offline mode fails every request', () async {
      mocks.offline.value = true;

      await expectLater(dio.get<dynamic>('https://api.test/anything'), throwsA(isA<DioException>()));
      expect(network.wasCalled, isFalse);
    });

    test('an unmatched request reaches the real server untouched', () async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders', statusCode: 500));

      final res = await dio.get<dynamic>('https://api.test/users');

      expect(res.statusCode, 200);
      expect(network.wasCalled, isTrue);
      expect(logs.entries.single.extras.keys, isNot(contains(kMockedExtraLabel)));
    });

    test('delayOnly still reaches the server', () async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders', action: MockAction.delayOnly));

      final res = await dio.get<dynamic>('https://api.test/orders');

      expect(res.statusCode, 200);
      expect(network.wasCalled, isTrue, reason: 'delayOnly delays, it does not fake');
    });
  });

  group('http adapter', () {
    late _ExplodingHttpClient network;
    late DebugHttpClient client;

    setUp(() {
      network = _ExplodingHttpClient();
      client = DebugHttpClient(network);
    });

    test('a respond rule fakes the response WITHOUT contacting the server', () async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders', statusCode: 503, body: '{"message":"down"}'));

      final res = await client.get(Uri.parse('https://api.test/orders'));

      expect(res.statusCode, 503);
      expect(res.body, '{"message":"down"}');
      expect(network.wasCalled, isFalse);
      expect(logs.entries.single.extras.keys, contains(kMockedExtraLabel));
    });

    test('a fail rule throws and never hits the server', () async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders', action: MockAction.fail));

      await expectLater(client.get(Uri.parse('https://api.test/orders')), throwsA(isA<http.ClientException>()));
      expect(network.wasCalled, isFalse);
    });

    test('an unmatched request reaches the real server', () async {
      final res = await client.get(Uri.parse('https://api.test/users'));

      expect(res.statusCode, 200);
      expect(network.wasCalled, isTrue);
    });

    test('an excluded URL is still mocked — excluding hides it, it does not exempt it', () async {
      logs.excludedUrlPatterns.add('/health');
      addTearDown(logs.excludedUrlPatterns.clear);

      mocks.add(const MockRule(id: 'r', urlPattern: '/health', statusCode: 500));

      final res = await client.get(Uri.parse('https://api.test/health'));

      expect(res.statusCode, 500);
      expect(network.wasCalled, isFalse);
      expect(logs.entries, isEmpty, reason: 'still excluded from the log');
    });
  });

  group('status classification', () {
    test('a REAL 500 under validateStatus:true is logged as failed, not success', () async {
      // Regression: onResponse used to hardcode success. dio only throws on
      // 4xx/5xx when validateStatus says so — apps that set
      // `validateStatus: (_) => true` had their 500s logged as green rows.
      // No mocking involved here.
      final dio = Dio()
        ..httpClientAdapter = _StatusDioAdapter(500)
        ..interceptors.add(DebugDioInterceptor());

      await dio.get<dynamic>('https://api.test/boom', options: Options(validateStatus: (_) => true));

      expect(logs.entries.single.status, NetworkLogStatus.failed);
      expect(logs.entries.single.statusCode, 500);
    });

    test('a real 200 is still success', () async {
      final dio = Dio()
        ..httpClientAdapter = _StatusDioAdapter(200)
        ..interceptors.add(DebugDioInterceptor());

      await dio.get<dynamic>('https://api.test/ok');

      expect(logs.entries.single.status, NetworkLogStatus.success);
    });
  });

  group('a mocked failure forwards to the Errors page', () {
    test('a faked 500 badges the launcher, like a real one', () async {
      final dio = Dio()
        ..httpClientAdapter = _ExplodingDioAdapter()
        ..interceptors.add(DebugDioInterceptor());

      mocks.add(const MockRule(id: 'r', urlPattern: '/orders', statusCode: 500));

      await dio.get<dynamic>('https://api.test/orders', options: Options(validateStatus: (_) => true));

      expect(LogStore.instance.entries.single.source, ErrorSource.network);
      expect(LogStore.instance.unseenErrorCount.value, 1);
    });
  });

  group('persistence', () {
    test('rules round-trip through storage', () async {
      final storage = InMemoryMockRuleStorage();
      mocks.storage = storage;
      addTearDown(() => mocks.storage = InMemoryMockRuleStorage());

      mocks.add(const MockRule(
        id: 'rule-7',
        urlPattern: '/orders',
        method: 'POST',
        isRegex: true,
        statusCode: 418,
        body: '{"a":1}',
        delay: Duration(milliseconds: 250),
      ));

      // Simulate a restart: wipe memory, reload from the same storage.
      mocks.rules.value = const [];
      await mocks.load();

      final rule = mocks.rules.value.single;
      expect(rule.id, 'rule-7');
      expect(rule.urlPattern, '/orders');
      expect(rule.method, 'POST');
      expect(rule.isRegex, isTrue);
      expect(rule.statusCode, 418);
      expect(rule.body, '{"a":1}');
      expect(rule.delay, const Duration(milliseconds: 250));
    });

    test('the id counter is seeded past loaded rules, so new ids do not collide', () async {
      final storage = InMemoryMockRuleStorage();
      mocks.storage = storage;
      addTearDown(() => mocks.storage = InMemoryMockRuleStorage());

      mocks.add(const MockRule(id: 'rule-5', urlPattern: '/a'));
      mocks.rules.value = const [];
      await mocks.load();

      // Without seeding, nextId() would restart at rule-0 and eventually reissue
      // rule-5, so update()/remove() would hit the wrong rule.
      expect(mocks.nextId(), isNot('rule-5'));
      expect(int.parse(mocks.nextId().replaceFirst('rule-', '')), greaterThan(5));
    });

    test('corrupt stored data is discarded, not thrown', () async {
      final storage = InMemoryMockRuleStorage();
      await storage.write('this is not json');
      mocks.storage = storage;
      addTearDown(() => mocks.storage = InMemoryMockRuleStorage());

      // A debug tool must not take the app down because its scratch file rotted.
      await mocks.load();
      expect(mocks.rules.value, isEmpty);
    });
  });

  group('isIntercepting', () {
    test('reports whether anything is currently faking traffic', () {
      expect(mocks.isIntercepting, isFalse);

      mocks.add(const MockRule(id: 'r', urlPattern: '/x'));
      expect(mocks.isIntercepting, isTrue);

      mocks.toggle('r');
      expect(mocks.isIntercepting, isFalse, reason: 'the only rule is now disabled');

      mocks.offline.value = true;
      expect(mocks.isIntercepting, isTrue);
    });
  });
}
