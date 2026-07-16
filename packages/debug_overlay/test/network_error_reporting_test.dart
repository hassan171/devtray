import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Completes a request with [status]/[code] and returns how many error-level
/// entries it pushed into the one LogStore.
int _failWith({int? code, String? errorMessage}) {
  final store = NetworkLogStore.instance;
  final entry = store.add(method: 'GET', uri: Uri.parse('https://x.test/thing'))!;
  store.complete(
    entry.id,
    status: NetworkLogStatus.failed,
    statusCode: code,
    errorMessage: errorMessage,
  );
  return LogStore.instance.entries.length;
}

void main() {
  setUp(() {
    NetworkLogStore.instance
      ..clear()
      // Pin serverAndTransport as the baseline for these tests (the product
      // default is `all` now — set on the page — but the store logic is what's
      // under test here, and each case sets the mode it needs).
      ..errorReporting.value = NetworkErrorReporting.serverAndTransport;
    LogStore.instance.clear();
  });

  group('network → errors forwarding', () {
    test('serverAndTransport forwards 5xx', () {
      expect(_failWith(code: 500), 1);
      expect(LogStore.instance.entries.single.source, ErrorSource.network);
    });

    test('serverAndTransport forwards transport failures (no status code)', () {
      expect(_failWith(errorMessage: 'Connection timed out'), 1);
    });

    test('serverAndTransport does NOT forward 4xx — a 404 probe should not badge', () {
      expect(_failWith(code: 404), 0);
      expect(LogStore.instance.unseenErrorCount.value, 0);
    });

    test('successful requests never forward', () {
      final store = NetworkLogStore.instance;
      final entry = store.add(method: 'GET', uri: Uri.parse('https://x.test/ok'))!;
      store.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);

      expect(LogStore.instance.entries, isEmpty);
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

    test('changing the mode takes effect immediately, mid-session', () {
      final store = NetworkLogStore.instance;

      expect(_failWith(code: 404), 0); // serverAndTransport: not reported
      store.errorReporting.value = NetworkErrorReporting.all;
      expect(_failWith(code: 404), 1); // now it is
    });

    test('a forwarded failure badges the launcher', () {
      _failWith(code: 503);
      expect(LogStore.instance.unseenErrorCount.value, 1);
    });

    test('NetworkError carries the entry and summarises itself', () {
      _failWith(code: 500);
      final error = LogStore.instance.entries.single.error;

      expect(error, isA<NetworkError>());
      expect((error as NetworkError).entry.statusCode, 500);
      expect(error.toString(), contains('HTTP 500'));
      expect(error.toString(), contains('GET https://x.test/thing'));
    });

    test('a transport failure summarises with its message, not a status', () {
      _failWith(errorMessage: 'Connection refused');
      expect(LogStore.instance.entries.single.error.toString(), contains('Connection refused'));
    });

    test('excluded URLs never reach the Errors page either', () {
      final store = NetworkLogStore.instance;
      store.excludedUrlPatterns.add('/health');
      addTearDown(store.excludedUrlPatterns.clear);

      // add() returns null for an excluded URL, so nothing is ever completed.
      expect(store.add(method: 'GET', uri: Uri.parse('https://x.test/health')), isNull);
      expect(LogStore.instance.entries, isEmpty);
    });
  });

  group('network error detail in the combined Logs page', () {
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
        home: Scaffold(body: DebugToolsScreen(pages: [LogsDebugPage()])),
      ));
      await tester.pumpAndSettle();

      // The forwarded error is a row in the Logs stream; expand it inline.
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

  group('NetworkDebugPage error-reporting param', () {
    testWidgets('defaults to reporting all failures', (tester) async {
      NetworkLogStore.instance.errorReporting.value = NetworkErrorReporting.none; // start off

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DebugToolsScreen(pages: [NetworkDebugPage()])),
      ));
      await tester.pumpAndSettle();

      expect(NetworkLogStore.instance.errorReporting.value, NetworkErrorReporting.all);
    });

    testWidgets('a narrower mode passed to the page is applied', (tester) async {
      NetworkLogStore.instance.errorReporting.value = NetworkErrorReporting.all;

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DebugToolsScreen(pages: [NetworkDebugPage(errorReporting: NetworkErrorReporting.none)])),
      ));
      await tester.pumpAndSettle();

      expect(NetworkLogStore.instance.errorReporting.value, NetworkErrorReporting.none);
    });
  });

  group('NetworkDebugPage panel', () {
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
