import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(DebugPage page) => MaterialApp(
      home: Scaffold(body: DebugToolsScreen(pages: [page])),
    );

void main() {
  late MockStore mocks;

  setUp(() {
    mocks = MockStore.instance
      ..enable()
      ..clear()
      ..offline.value = false
      ..rulesEnabled.value = true;
    NetworkLogStore.instance.clear();
  });

  group('MocksDebugPage', () {
    testWidgets('shows an empty state that points at the seeded flow', (tester) async {
      await tester.pumpWidget(_host(const MocksDebugPage()));
      await tester.pumpAndSettle();

      expect(find.text('No mock rules'), findsOneWidget);
      expect(find.textContaining('Mock this'), findsOneWidget);
    });

    testWidgets('lists rules and toggles one off', (tester) async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders', statusCode: 500));

      await tester.pumpWidget(_host(const MocksDebugPage()));
      await tester.pumpAndSettle();

      expect(find.text('/orders'), findsOneWidget);
      expect(find.text('HTTP 500'), findsOneWidget);

      // The rule's own switch (the two master switches come first).
      await tester.tap(find.byType(Switch).at(2));
      await tester.pumpAndSettle();

      expect(mocks.rules.value.single.enabled, isFalse);
    });

    testWidgets('deletes a rule', (tester) async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders'));

      await tester.pumpWidget(_host(const MocksDebugPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(mocks.rules.value, isEmpty);
    });

    testWidgets('the offline master switch flips the store', (tester) async {
      await tester.pumpWidget(_host(const MocksDebugPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(mocks.offline.value, isTrue);
    });
  });

  group('MockInterceptionBanner — the "did I fake this?" guard', () {
    testWidgets('hidden when nothing is intercepting', (tester) async {
      await tester.pumpWidget(_host(const MocksDebugPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('active'), findsNothing);
      expect(find.textContaining('Offline mode is ON'), findsNothing);
    });

    testWidgets('warns when a rule is active', (tester) async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders'));

      await tester.pumpWidget(_host(const MocksDebugPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 mock rule active'), findsOneWidget);
    });

    testWidgets('warns when offline mode is on', (tester) async {
      mocks.offline.value = true;

      await tester.pumpWidget(_host(const MocksDebugPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Offline mode is ON'), findsOneWidget);
    });

    testWidgets('"Turn off" kills all interception in one tap', (tester) async {
      mocks
        ..offline.value = true
        ..add(const MockRule(id: 'r', urlPattern: '/orders'));

      await tester.pumpWidget(_host(const MocksDebugPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();

      expect(mocks.isIntercepting, isFalse);
      expect(mocks.rules.value, hasLength(1), reason: 'parked, not deleted');
    });

    testWidgets('also appears on the Network page', (tester) async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders'));

      await tester.pumpWidget(_host(const NetworkDebugPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 mock rule active'), findsOneWidget);
    });
  });

  group('MOCKED badge on the request list', () {
    testWidgets('a mocked entry is badged; a real one is not', (tester) async {
      final logs = NetworkLogStore.instance;

      final mocked = logs.add(method: 'GET', uri: Uri.parse('https://api.test/orders'))!;
      logs.complete(mocked.id, status: NetworkLogStatus.failed, statusCode: 500);
      logs.attachExtra(mocked.id, kMockedExtraLabel, 'faked');

      final real = logs.add(method: 'GET', uri: Uri.parse('https://api.test/users'))!;
      logs.complete(real.id, status: NetworkLogStatus.success, statusCode: 200);

      await tester.pumpWidget(_host(const NetworkDebugPage()));
      await tester.pumpAndSettle();

      // Exactly one badge, for exactly one of the two rows.
      expect(find.text('MOCKED'), findsOneWidget);
      expect(find.text('/orders'), findsOneWidget);
      expect(find.text('/users'), findsOneWidget);
    });
  });

  group('opting out of mocking entirely', () {
    testWidgets('enableMocking: false hides the "Mock this request" button', (tester) async {
      final logs = NetworkLogStore.instance;
      final entry = logs.add(method: 'GET', uri: Uri.parse('https://api.test/orders'))!;
      logs.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);

      await tester.pumpWidget(_host(const NetworkDebugPage(enableMocking: false)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('/orders'));
      await tester.pumpAndSettle();

      // Without a MocksDebugPage registered, this button would create a rule the
      // user can't see, edit or delete.
      expect(find.byTooltip('Mock this request'), findsNothing);
      // The rest of the detail is untouched.
      expect(find.byTooltip('Copy as cURL'), findsOneWidget);
    });

    testWidgets('enableMocking: false hides the interception banner', (tester) async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders'));

      await tester.pumpWidget(_host(const NetworkDebugPage(enableMocking: false)));
      await tester.pumpAndSettle();

      expect(find.textContaining('mock rule active'), findsNothing);
    });

    testWidgets('by default the button IS shown', (tester) async {
      final logs = NetworkLogStore.instance;
      final entry = logs.add(method: 'GET', uri: Uri.parse('https://api.test/orders'))!;
      logs.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);

      await tester.pumpWidget(_host(const NetworkDebugPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('/orders'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Mock this request'), findsOneWidget);
    });

    test('MockStore.disable() stops interception for real, not just in the UI', () {
      // Hiding the UI is not enough — the adapters consult the store regardless
      // of which pages are registered, so a rule added from code would still
      // fake traffic with nothing on screen to reveal it.
      mocks
        ..add(const MockRule(id: 'r', urlPattern: '/orders', statusCode: 500))
        ..offline.value = true;

      expect(mocks.isIntercepting, isTrue);

      mocks.disable();
      addTearDown(mocks.enable);

      expect(mocks.isIntercepting, isFalse);
      expect(mocks.ruleFor(url: 'https://api.test/orders', method: 'GET'), isNull);

      // disable() beats offline mode too.
      expect(decideMock(url: 'https://api.test/orders', method: 'GET'), isA<PassThrough>());
    });
  });

  group('MockRuleEditor', () {
    testWidgets('seeds a new rule from a captured request, prefilling its body', (tester) async {
      final logs = NetworkLogStore.instance;
      final entry = logs.add(method: 'POST', uri: Uri.parse('https://api.test/v1/orders'))!;
      logs.complete(
        entry.id,
        status: NetworkLogStatus.success,
        statusCode: 200,
        responseBody: {'items': []},
      );

      await tester.pumpWidget(_host(const NetworkDebugPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('/v1/orders'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mock this request'));
      await tester.pumpAndSettle();

      expect(find.text('New mock rule'), findsOneWidget);

      // Prefilled from the real request: path (not the full URL — a host-keyed
      // rule would break when you switch environments), method, status, body.
      expect(find.widgetWithText(TextField, '/v1/orders'), findsOneWidget);
      expect(find.widgetWithText(TextField, '200'), findsOneWidget);
      expect(find.textContaining('"items"'), findsOneWidget);
    });

    testWidgets('rejects an invalid JSON body rather than saving it', (tester) async {
      await tester.pumpWidget(_host(const MocksDebugPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '/orders'), '/x');
      await tester.enterText(find.widgetWithText(TextField, '{"message": "boom"}'), '{ broken json');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid JSON'), findsOneWidget);
      expect(mocks.rules.value, isEmpty, reason: 'must not save a body it could not parse');
    });

    testWidgets('a non-JSON body is accepted — plain text is legitimate', (tester) async {
      await tester.pumpWidget(_host(const MocksDebugPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '/orders'), '/x');
      await tester.enterText(find.widgetWithText(TextField, '{"message": "boom"}'), 'plain text body');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();

      expect(mocks.rules.value.single.body, 'plain text body');
    });

    testWidgets('saves a rule with all its fields', (tester) async {
      await tester.pumpWidget(_host(const MocksDebugPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '/orders'), '/checkout');
      await tester.enterText(find.widgetWithText(TextField, '500'), '503');
      await tester.enterText(find.widgetWithText(TextField, '0'), '250');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();

      final rule = mocks.rules.value.single;
      expect(rule.urlPattern, '/checkout');
      expect(rule.statusCode, 503);
      expect(rule.delay, const Duration(milliseconds: 250));
      expect(rule.enabled, isTrue);
    });
  });
}
