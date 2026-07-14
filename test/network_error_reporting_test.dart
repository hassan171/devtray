import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Completes a request with [status]/[code] and returns how many errors it
/// pushed onto the Errors page.
int _failWith({int? code, String? errorMessage}) {
  final store = NetworkLogStore.instance;
  final entry = store.add(method: 'GET', uri: Uri.parse('https://x.test/thing'))!;
  store.complete(
    entry.id,
    status: NetworkLogStatus.failed,
    statusCode: code,
    errorMessage: errorMessage,
  );
  return ErrorStore.instance.entries.length;
}

void main() {
  setUp(() {
    NetworkLogStore.instance
      ..clear()
      ..errorReporting.value = NetworkErrorReporting.serverAndTransport;
    ErrorStore.instance.clear();
  });

  group('network → errors forwarding', () {
    test('default policy forwards 5xx', () {
      expect(_failWith(code: 500), 1);
      expect(ErrorStore.instance.entries.single.source, ErrorSource.network);
    });

    test('default policy forwards transport failures (no status code)', () {
      expect(_failWith(errorMessage: 'Connection timed out'), 1);
    });

    test('default policy does NOT forward 4xx — a 404 probe should not badge', () {
      expect(_failWith(code: 404), 0);
      expect(ErrorStore.instance.unseenCount.value, 0);
    });

    test('successful requests never forward', () {
      final store = NetworkLogStore.instance;
      final entry = store.add(method: 'GET', uri: Uri.parse('https://x.test/ok'))!;
      store.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);

      expect(ErrorStore.instance.entries, isEmpty);
    });

    test('"all" forwards 4xx too', () {
      NetworkLogStore.instance.errorReporting.value = NetworkErrorReporting.all;
      expect(_failWith(code: 404), 1);
    });

    test('"none" forwards nothing', () {
      NetworkLogStore.instance.errorReporting.value = NetworkErrorReporting.none;
      expect(_failWith(code: 500), 0);
      expect(_failWith(errorMessage: 'timeout'), 0);
    });

    test('the toggle takes effect immediately, mid-session', () {
      final store = NetworkLogStore.instance;

      expect(_failWith(code: 404), 0); // default: not reported
      store.errorReporting.value = NetworkErrorReporting.all;
      expect(_failWith(code: 404), 1); // now it is
    });

    test('a forwarded failure badges the launcher', () {
      _failWith(code: 503);
      expect(ErrorStore.instance.unseenCount.value, 1);
    });

    test('NetworkError carries the entry and summarises itself', () {
      _failWith(code: 500);
      final error = ErrorStore.instance.entries.single.error;

      expect(error, isA<NetworkError>());
      expect((error as NetworkError).entry.statusCode, 500);
      expect(error.toString(), contains('HTTP 500'));
      expect(error.toString(), contains('GET https://x.test/thing'));
    });

    test('a transport failure summarises with its message, not a status', () {
      _failWith(errorMessage: 'Connection refused');
      expect(ErrorStore.instance.entries.single.error.toString(), contains('Connection refused'));
    });

    test('excluded URLs never reach the Errors page either', () {
      final store = NetworkLogStore.instance;
      store.excludedUrlPatterns.add('/health');
      addTearDown(store.excludedUrlPatterns.clear);

      // add() returns null for an excluded URL, so nothing is ever completed.
      expect(store.add(method: 'GET', uri: Uri.parse('https://x.test/health')), isNull);
      expect(ErrorStore.instance.entries, isEmpty);
    });
  });

  group('ErrorsDebugPage network detail', () {
    testWidgets('shows the request/response instead of an empty stack trace', (tester) async {
      final store = NetworkLogStore.instance;
      final entry = store.add(
        method: 'POST',
        uri: Uri.parse('https://x.test/orders'),
        requestHeaders: {'Authorization': 'Bearer t'},
      )!;
      store.complete(
        entry.id,
        status: NetworkLogStatus.failed,
        statusCode: 500,
        responseHeaders: {
          'content-type': ['application/json'],
        },
        responseBody: {'message': 'boom'},
      );

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DebugToolsScreen(pages: [ErrorsDebugPage()])),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('HTTP 500'));
      await tester.pumpAndSettle();

      expect(find.text('Request'), findsOneWidget);
      expect(find.text('Response Body'), findsOneWidget);
      // A transport/HTTP failure has no meaningful Dart stack — we must not
      // show a "No stack trace" section in its place.
      expect(find.text('Stack Trace'), findsNothing);
      expect(find.textContaining('boom'), findsOneWidget);
    });
  });

  group('NetworkErrorReportingButton', () {
    testWidgets('changes the policy from the Network page', (tester) async {
      // Mount the way a real app does — DebugOverlay ABOVE MaterialApp, opened
      // through the launcher. Hosting DebugToolsScreen inside a MaterialApp
      // instead would lend the panel the app's Navigator, hiding the fact that
      // PopupMenuButton needs one (it calls Navigator.of) when there is none.
      final controller = DebugOverlayController();
      await tester.pumpWidget(DebugOverlay(
        controller: controller,
        pages: const [NetworkDebugPage()],
        child: const MaterialApp(home: Scaffold(body: Text('app'))),
      ));

      controller.open();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NetworkErrorReportingButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Report all failures (incl. 4xx)'));
      await tester.pumpAndSettle();

      expect(NetworkLogStore.instance.errorReporting.value, NetworkErrorReporting.all);
    });

    testWidgets('the HTML preview dialog opens from inside the panel', (tester) async {
      // Same trap as the popup menu: showDialog() calls Navigator.of(), and the
      // panel sits above MaterialApp where there is none.
      final store = NetworkLogStore.instance;
      final entry = store.add(method: 'GET', uri: Uri.parse('https://x.test/page'))!;
      store.complete(
        entry.id,
        status: NetworkLogStatus.success,
        statusCode: 200,
        responseHeaders: {
          'content-type': ['text/html'],
        },
        responseBody: '<html><body><h1>hello</h1></body></html>',
      );

      final controller = DebugOverlayController();
      await tester.pumpWidget(DebugOverlay(
        controller: controller,
        presentation: DebugOverlayPresentation.fullscreen,
        pages: const [NetworkDebugPage()],
        child: const MaterialApp(home: Scaffold(body: Text('app'))),
      ));

      controller.open();
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('/page'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Preview HTML'));
      await tester.pumpAndSettle();

      expect(find.text('HTML Preview'), findsOneWidget);
    });
  });
}
