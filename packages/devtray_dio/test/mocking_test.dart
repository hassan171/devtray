import 'dart:typed_data';

import 'package:devtray/devtray.dart';
import 'package:devtray_dio/devtray_dio.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
