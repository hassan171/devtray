import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({
  bool enabled = true,
  bool showLauncher = true,
  List<DebugPage> pages = const [NetworkDebugPage()],
}) {
  return DevtrayOverlay(
    enabled: enabled,
    showLauncher: showLauncher,
    pages: pages,
    child: const MaterialApp(home: Scaffold(body: Text('app'))),
  );
}

void main() {
  setUp(() {
    DevtrayNet.instance.clear();
    // Panel state is process-global now, so a test that leaves it open would
    // otherwise start the next one mid-flight.
    Devtray.reset();
  });

  group('DevtrayOverlay', () {
    testWidgets('renders the launcher and opens the tools on tap', (tester) async {
      await tester.pumpWidget(_app());
      expect(find.byIcon(Icons.bug_report), findsOneWidget);

      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pumpAndSettle();

      expect(find.byType(DebugToolsScreen), findsOneWidget);
      expect(find.text('Network'), findsOneWidget);
      // Launcher hides while open, so it can't be reopened on top of itself.
      expect(find.byIcon(Icons.bug_report), findsNothing);
    });

    testWidgets('enabled: false renders nothing', (tester) async {
      await tester.pumpWidget(_app(enabled: false));
      expect(find.byIcon(Icons.bug_report), findsNothing);
      expect(find.text('app'), findsOneWidget);
    });

    testWidgets('Devtray.open() works with the launcher hidden', (tester) async {
      await tester.pumpWidget(_app(showLauncher: false));

      expect(find.byIcon(Icons.bug_report), findsNothing);

      Devtray.open();
      await tester.pumpAndSettle();
      expect(find.byType(DebugToolsScreen), findsOneWidget);
    });

    testWidgets('dismissing via the close button resyncs Devtray.isOpen', (tester) async {
      await tester.pumpWidget(_app());

      Devtray.open();
      await tester.pumpAndSettle();
      expect(Devtray.isOpen, isTrue);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Must be back to closed and the launcher back on screen, otherwise the
      // overlay can never be reopened.
      expect(Devtray.isOpen, isFalse);
      expect(find.byType(DebugToolsScreen), findsNothing);
      expect(find.byIcon(Icons.bug_report), findsOneWidget);
    });

    testWidgets('dismissing via the barrier resyncs Devtray.isOpen', (tester) async {
      await tester.pumpWidget(_app());

      Devtray.open();
      await tester.pumpAndSettle();

      // Tap outside the dialog.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(Devtray.isOpen, isFalse);
      expect(find.byIcon(Icons.bug_report), findsOneWidget);
    });

    testWidgets('custom pages render as tabs', (tester) async {
      await tester.pumpWidget(_app(
        pages: [
          const NetworkDebugPage(),
          DebugPage.builder(title: 'Env', builder: (_) => const Text('env body')),
        ],
      ));

      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Env'));
      await tester.pumpAndSettle();
      expect(find.text('env body'), findsOneWidget);
    });
  });

  group('DevtrayNet', () {
    test('add/complete records an entry', () {
      final store = DevtrayNet.instance;
      final entry = store.add(method: 'GET', uri: Uri.parse('https://x.test/a'));

      expect(entry, isNotNull);
      expect(entry!.status, NetworkLogStatus.pending);

      store.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200, responseBody: {'ok': true});

      expect(store.entries.single.statusCode, 200);
      expect(store.entries.single.status, NetworkLogStatus.success);
      expect(store.entries.single.duration, isNotNull);
    });

    test('excluded URLs are not recorded', () {
      final store = DevtrayNet.instance;
      store.excludedUrlPatterns.add('/health');
      addTearDown(store.excludedUrlPatterns.clear);

      expect(store.add(method: 'GET', uri: Uri.parse('https://x.test/health')), isNull);
      expect(store.entries, isEmpty);
    });

    test('drops the oldest entry past maxEntries', () {
      final store = DevtrayNet.instance;
      store.maxEntries = 2;
      addTearDown(() => store.maxEntries = 500);

      for (var i = 0; i < 3; i++) {
        store.add(method: 'GET', uri: Uri.parse('https://x.test/$i'));
      }

      expect(store.entries.length, 2);
      // Newest first; /0 was evicted.
      expect(store.entries.first.uri.path, '/2');
      expect(store.entries.last.uri.path, '/1');
    });
  });

  group('buildCurl', () {
    test('renders headers and a JSON body', () {
      final curl = buildCurl(
        method: 'post',
        uri: Uri.parse('https://x.test/a'),
        headers: {'Authorization': 'Bearer t'},
        data: {'a': 1},
      );

      expect(curl, contains('curl -X POST'));
      // Auth included, verbatim — the point of copying a request as cURL is to
      // be able to replay it, which you can't do with the token stripped.
      expect(curl, contains("-H 'Authorization: Bearer t'"));
      expect(curl, contains(r'-d ' "'" r'{"a":1}' "'"));
      expect(curl, contains("'https://x.test/a'"));
    });

    test('renders a multipart snapshot as -F flags and drops content-type', () {
      final curl = buildCurl(
        method: 'POST',
        uri: Uri.parse('https://x.test/upload'),
        headers: {'content-type': 'application/json'},
        data: {
          kFormDataMarker: true,
          'fields': {'name': 'x'},
          'files': [
            {'key': 'file', 'filename': 'a.png'},
          ],
        },
      );

      expect(curl, contains("-F 'name=x'"));
      expect(curl, contains("-F 'file=@a.png'"));
      // curl must set the multipart boundary itself.
      expect(curl, isNot(contains('content-type')));
      expect(curl, isNot(contains('-d ')));
    });
  });
}
