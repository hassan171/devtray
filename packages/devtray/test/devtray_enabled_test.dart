import 'package:devtray/devtray.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    Devtray.reset();
    DevtrayNet.instance.clear();
    DevtrayLog.instance.clear();
    DevtrayLog.instance.clear();
    DevtrayMocks.instance
      ..enable()
      ..clear()
      ..offline.value = false;
  });
  tearDown(Devtray.reset);

  test('defaults to kDebugMode — a release build captures nothing by default', () {
    // The whole point: you shouldn't have to remember anything.
    expect(Devtray.enabled, kDebugMode);
  });

  group('when off, every store is a no-op', () {
    setUp(() => Devtray.enabled = false);

    test('network requests are not captured', () {
      final entry = DevtrayNet.instance.add(
        method: 'POST',
        uri: Uri.parse('https://api.test/login'),
        requestHeaders: {'Authorization': 'Bearer live-token'},
        requestBody: {'password': 'hunter2'},
      );

      // This is the gap it closes: the adapters are installed by the host app,
      // so in a release build they'd otherwise keep buffering 500 requests —
      // tokens, bodies and all — that nothing will ever read.
      expect(entry, isNull);
      expect(DevtrayNet.instance.entries, isEmpty);
    });

    test('logs are not captured', () {
      DevtrayLog.instance.log('something');
      expect(DevtrayLog.instance.entries, isEmpty);
    });

    test('errors are not captured, and the launcher badge stays at zero', () {
      DevtrayLog.instance.report(StateError('boom'));

      expect(DevtrayLog.instance.entries, isEmpty);
      expect(DevtrayLog.instance.unseenErrorCount.value, 0);
    });

    test('mocks never intercept — the worst thing this package could do', () {
      DevtrayMocks.instance
        ..add(const MockRule(id: 'r', urlPattern: '/orders', statusCode: 500))
        ..offline.value = true;

      // Beats an active rule AND offline mode.
      expect(decideMock(url: 'https://api.test/orders', method: 'GET'), isA<PassThrough>());
    });
  });

  group('turning it off mid-session', () {
    test('drops whatever was already captured', () {
      DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/x'));
      DevtrayLog.instance.log('secret');
      DevtrayLog.instance.report('boom');

      expect(DevtrayNet.instance.entries, isNotEmpty);
      expect(DevtrayLog.instance.entries, isNotEmpty);
      expect(DevtrayLog.instance.entries, isNotEmpty);

      Devtray.enabled = false;

      // Otherwise flipping the switch would leave the very buffer of traffic it
      // exists to prevent.
      expect(DevtrayNet.instance.entries, isEmpty);
      expect(DevtrayLog.instance.entries, isEmpty);
      expect(DevtrayLog.instance.entries, isEmpty);
    });

    test('turning it back on resumes capture', () {
      Devtray.enabled = false;
      expect(DevtrayLog.instance.log, isNotNull); // no-op, no throw
      DevtrayLog.instance.log('dropped');
      expect(DevtrayLog.instance.entries, isEmpty);

      Devtray.enabled = true;
      DevtrayLog.instance.log('kept');

      expect(DevtrayLog.instance.entries.single.message, 'kept');
    });
  });
}
