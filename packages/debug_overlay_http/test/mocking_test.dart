import 'dart:convert';

import 'package:debug_overlay/debug_overlay.dart';
import 'package:debug_overlay_http/debug_overlay_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

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
}
