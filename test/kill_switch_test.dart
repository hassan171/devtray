import 'package:debug_overlay/debug_overlay.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A dio adapter that records whether the real network was reached.
class _FakeAdapter implements HttpClientAdapter {
  bool wasCalled = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    wasCalled = true;
    return ResponseBody.fromString('{}', 200, headers: {
      'content-type': ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    DebugOverlayKillSwitch.reset();
    NetworkLogStore.instance.clear();
    LogStore.instance.clear();
    LogStore.instance.clear();
    MockStore.instance
      ..enable()
      ..clear()
      ..offline.value = false;
  });
  tearDown(DebugOverlayKillSwitch.reset);

  test('defaults to kDebugMode — a release build captures nothing by default', () {
    // The whole point: you shouldn't have to remember anything.
    expect(DebugOverlayKillSwitch.enabled, kDebugMode);
  });

  group('when off, every store is a no-op', () {
    setUp(() => DebugOverlayKillSwitch.enabled = false);

    test('network requests are not captured', () {
      final entry = NetworkLogStore.instance.add(
        method: 'POST',
        uri: Uri.parse('https://api.test/login'),
        requestHeaders: {'Authorization': 'Bearer live-token'},
        requestBody: {'password': 'hunter2'},
      );

      // This is the gap it closes: the adapters are installed by the host app,
      // so in a release build they'd otherwise keep buffering 500 requests —
      // tokens, bodies and all — that nothing will ever read.
      expect(entry, isNull);
      expect(NetworkLogStore.instance.entries, isEmpty);
    });

    test('logs are not captured', () {
      LogStore.instance.log('something');
      expect(LogStore.instance.entries, isEmpty);
    });

    test('errors are not captured, and the launcher badge stays at zero', () {
      LogStore.instance.report(StateError('boom'));

      expect(LogStore.instance.entries, isEmpty);
      expect(LogStore.instance.unseenErrorCount.value, 0);
    });

    test('mocks never intercept — the worst thing this package could do', () {
      MockStore.instance
        ..add(const MockRule(id: 'r', urlPattern: '/orders', statusCode: 500))
        ..offline.value = true;

      // Beats an active rule AND offline mode.
      expect(decideMock(url: 'https://api.test/orders', method: 'GET'), isA<PassThrough>());
    });
  });

  group('turning it off mid-session', () {
    test('drops whatever was already captured', () {
      NetworkLogStore.instance.add(method: 'GET', uri: Uri.parse('https://api.test/x'));
      LogStore.instance.log('secret');
      LogStore.instance.report('boom');

      expect(NetworkLogStore.instance.entries, isNotEmpty);
      expect(LogStore.instance.entries, isNotEmpty);
      expect(LogStore.instance.entries, isNotEmpty);

      DebugOverlayKillSwitch.enabled = false;

      // Otherwise flipping the switch would leave the very buffer of traffic it
      // exists to prevent.
      expect(NetworkLogStore.instance.entries, isEmpty);
      expect(LogStore.instance.entries, isEmpty);
      expect(LogStore.instance.entries, isEmpty);
    });

    test('turning it back on resumes capture', () {
      DebugOverlayKillSwitch.enabled = false;
      expect(LogStore.instance.log, isNotNull); // no-op, no throw
      LogStore.instance.log('dropped');
      expect(LogStore.instance.entries, isEmpty);

      DebugOverlayKillSwitch.enabled = true;
      LogStore.instance.log('kept');

      expect(LogStore.instance.entries.single.message, 'kept');
    });
  });

  group('the dio adapter with the switch off', () {
    test('requests still reach the real server — the app must not break', () {
      DebugOverlayKillSwitch.enabled = false;

      final network = _FakeAdapter();
      final dio = Dio()
        ..httpClientAdapter = network
        ..interceptors.add(DebugDioInterceptor());

      // The interceptor is still installed. It must become a passthrough, not a
      // wall — disabling the debug tools cannot break the app's networking.
      return dio.get<dynamic>('https://api.test/x').then((res) {
        expect(res.statusCode, 200);
        expect(network.wasCalled, isTrue);
        expect(NetworkLogStore.instance.entries, isEmpty);
      });
    });
  });
}
