import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mocks are no longer a page — they render as [MocksView] inside the Network
/// tab. The view is self-contained (reads MockStore directly), so host it in a
/// bare Scaffold, sized so its Expanded list has bounded height.
Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(height: 600, child: child)),
    );

/// For the DebugPage-based tests (the Network tab), which need the tools screen.
Widget _hostPage(DebugPage page) => MaterialApp(
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

  group('MocksView', () {
    testWidgets('shows an empty state that points at the seeded flow', (tester) async {
      await tester.pumpWidget(_host(const MocksView()));
      await tester.pumpAndSettle();

      expect(find.text('No mock rules'), findsOneWidget);
      expect(find.textContaining('Mock this'), findsOneWidget);
    });

    testWidgets('lists rules and toggles one off', (tester) async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders', statusCode: 500));

      await tester.pumpWidget(_host(const MocksView()));
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

      await tester.pumpWidget(_host(const MocksView()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(mocks.rules.value, isEmpty);
    });

    testWidgets('the offline master switch flips the store', (tester) async {
      await tester.pumpWidget(_host(const MocksView()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(mocks.offline.value, isTrue);
    });
  });

  group('the "did I fake this?" guard on the Network page', () {
    // The warning lives in the Network toolbar's Mocks button, not in a banner.
    // A banner was a sibling in the page's Column, so showing it shoved every
    // request row down the moment a mock was toggled. What must stay true: while
    // anything is intercepting, the Network page says so — and says how loudly.


    testWidgets('silent when nothing is intercepting', (tester) async {
      await tester.pumpWidget(_hostPage(const NetworkDebugPage()));
      await tester.pumpAndSettle();

      expect(find.byTooltip(RegExp('Tap to manage'), skipOffstage: false), findsNothing);
      expect(find.byTooltip('Mocks'), findsOneWidget, reason: 'still reachable, just not warning');
    });

    testWidgets('warns on the Network page when a rule is active', (tester) async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders'));

      await tester.pumpWidget(_hostPage(const NetworkDebugPage()));
      await tester.pumpAndSettle();

      expect(find.byTooltip(RegExp('1 mock rule active'), skipOffstage: false), findsOneWidget);
    });

    testWidgets('warns on the Network page when offline mode is on', (tester) async {
      mocks.offline.value = true;

      await tester.pumpWidget(_hostPage(const NetworkDebugPage()));
      await tester.pumpAndSettle();

      expect(find.byTooltip(RegExp('every request is being failed'), skipOffstage: false), findsOneWidget);
    });

    testWidgets('the warning does not move the request list', (tester) async {
      // The whole point of moving it into the toolbar. Toggling interception
      // must not shift a single row.
      final logs = NetworkLogStore.instance;
      final e = logs.add(method: 'GET', uri: Uri.parse('https://api.test/users'))!;
      logs.complete(e.id, status: NetworkLogStatus.success, statusCode: 200);

      await tester.pumpWidget(_hostPage(const NetworkDebugPage()));
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.text('/users'));

      mocks.add(const MockRule(id: 'r', urlPattern: '/orders'));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('/users')), before, reason: 'interception must not shift the list');
    });

    testWidgets('the Mocks button is the same size armed or not', (tester) async {
      await tester.pumpWidget(_hostPage(const NetworkDebugPage()));
      await tester.pumpAndSettle();
      final idle = tester.getSize(find.byTooltip('Mocks'));

      mocks.offline.value = true; // the widest possible state
      await tester.pumpAndSettle();
      final armed = tester.getSize(find.byTooltip(RegExp('failed'), skipOffstage: false));

      expect(armed, idle, reason: 'a resizing button would nudge the toolbar');
    });
  });

  group('MockInterceptionBanner — still available for host layouts', () {
    // No longer used by the built-in pages, but exported, so a host can put the
    // warning wherever their own chrome has room for it.

    testWidgets('hidden when nothing is intercepting', (tester) async {
      await tester.pumpWidget(_host(const MockInterceptionBanner()));
      await tester.pumpAndSettle();

      expect(find.textContaining('active'), findsNothing);
      expect(find.textContaining('Offline mode is ON'), findsNothing);
    });

    testWidgets('warns when a rule is active', (tester) async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders'));

      await tester.pumpWidget(_host(const MockInterceptionBanner()));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 mock rule active'), findsOneWidget);
    });

    testWidgets('warns when offline mode is on', (tester) async {
      mocks.offline.value = true;

      await tester.pumpWidget(_host(const MockInterceptionBanner()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Offline mode is ON'), findsOneWidget);
    });

    testWidgets('"Turn off" kills all interception in one tap', (tester) async {
      mocks
        ..offline.value = true
        ..add(const MockRule(id: 'r', urlPattern: '/orders'));

      await tester.pumpWidget(_host(const MockInterceptionBanner()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();

      expect(mocks.isIntercepting, isFalse);
      expect(mocks.rules.value, hasLength(1), reason: 'parked, not deleted');
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

      await tester.pumpWidget(_hostPage(const NetworkDebugPage()));
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

      await tester.pumpWidget(_hostPage(const NetworkDebugPage(enableMocking: false)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('/orders'));
      await tester.pumpAndSettle();

      // With mocking off there's no Mocks button either, so this rule would be
      // unreachable — hence the button is hidden.
      expect(find.byTooltip('Mock this request'), findsNothing);
      // The rest of the detail is untouched.
      expect(find.byTooltip('Copy as cURL'), findsOneWidget);
    });

    testWidgets('enableMocking: false hides the interception banner', (tester) async {
      mocks.add(const MockRule(id: 'r', urlPattern: '/orders'));

      await tester.pumpWidget(_hostPage(const NetworkDebugPage(enableMocking: false)));
      await tester.pumpAndSettle();

      expect(find.textContaining('mock rule active'), findsNothing);
    });

    testWidgets('by default the button IS shown', (tester) async {
      final logs = NetworkLogStore.instance;
      final entry = logs.add(method: 'GET', uri: Uri.parse('https://api.test/orders'))!;
      logs.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);

      await tester.pumpWidget(_hostPage(const NetworkDebugPage()));
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

  group('Mocks button inside the Network tab', () {
    testWidgets('opens the MocksView and the back arrow returns to the list', (tester) async {
      final logs = NetworkLogStore.instance;
      final entry = logs.add(method: 'GET', uri: Uri.parse('https://api.test/orders'))!;
      logs.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);
      mocks.add(const MockRule(id: 'r', urlPattern: '/rules-list'));

      await tester.pumpWidget(_hostPage(const NetworkDebugPage()));
      await tester.pumpAndSettle();

      // The request list is showing.
      expect(find.text('/orders'), findsOneWidget);

      // Tap the toolbar Mocks button → the mocking UI takes over the tab.
      // A rule is seeded above, so the button is in its armed state and its
      // tooltip is the warning rather than plain 'Mocks'.
      await tester.tap(find.byTooltip(RegExp('Tap to manage'), skipOffstage: false));
      await tester.pumpAndSettle();

      expect(find.text('/rules-list'), findsOneWidget, reason: 'mock rule listed');
      expect(find.text('/orders'), findsNothing, reason: 'the request list is hidden');

      // Back arrow returns to the request list.
      await tester.tap(find.byTooltip('Back to requests'));
      await tester.pumpAndSettle();

      expect(find.text('/orders'), findsOneWidget);
    });

    testWidgets('enableMocking: false hides the Mocks button', (tester) async {
      await tester.pumpWidget(_hostPage(const NetworkDebugPage(enableMocking: false)));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Mocks'), findsNothing);
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

      await tester.pumpWidget(_hostPage(const NetworkDebugPage()));
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
      await tester.pumpWidget(_host(const MocksView()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New rule'));
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
      await tester.pumpWidget(_host(const MocksView()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New rule'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '/orders'), '/x');
      await tester.enterText(find.widgetWithText(TextField, '{"message": "boom"}'), 'plain text body');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();

      expect(mocks.rules.value.single.body, 'plain text body');
    });

    testWidgets('saves a rule with all its fields', (tester) async {
      await tester.pumpWidget(_host(const MocksView()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New rule'));
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
