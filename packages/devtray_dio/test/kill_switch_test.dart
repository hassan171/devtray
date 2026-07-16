import 'package:devtray/devtray.dart';
import 'package:devtray_dio/devtray_dio.dart';
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
    DevtrayKillSwitch.enabled = true;
    NetworkLogStore.instance.clear();
  });

  tearDown(() => DevtrayKillSwitch.enabled = true);

  group('the dio adapter with the switch off', () {
    // The kill switch's *logic* is tested in the core package. This is the part
    // only dio can answer: that the interceptor you installed stays harmless
    // when the tools are off.
    test('requests still reach the real server — the app must not break', () {
      DevtrayKillSwitch.enabled = false;

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
