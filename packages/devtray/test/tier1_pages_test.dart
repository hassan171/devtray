import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(DebugPage page) {
  return MaterialApp(
    home: Scaffold(
      body: DebugToolsScreen(pages: [page]),
    ),
  );
}

void main() {
  setUp(() {
    DevtrayLog.instance.clear();
  });

  group('DevtrayLog', () {
    test('records, caps, and exposes tags', () {
      final store = DevtrayLog.instance;
      store.maxEntries = 2;
      addTearDown(() => store.maxEntries = 1000);

      store.log('a', tag: 'auth');
      store.log('b', tag: 'net', level: LogLevel.error);
      store.log('c');

      expect(store.entries.length, 2);
      expect(store.entries.first.message, 'c'); // newest first
      expect(store.tags, {'net'}); // 'auth' was evicted with entry 'a'
    });

    test('captureDebugPrint routes debugPrint into the store and still prints', () {
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (msg, {wrapWidth}) => printed.add(msg ?? '');

      captureDebugPrint();
      addTearDown(() {
        stopCapturingDebugPrint();
        debugPrint = original;
      });

      debugPrint('hello');

      expect(DevtrayLog.instance.entries.single.message, 'hello');
      // Observed, not swallowed — the original handler still ran.
      expect(printed, ['hello']);
    });
  });

  group('notification coalescing (freeze guard)', () {
    // Regression: framework errors are reported *during* a build. If the store
    // notified its listeners synchronously from there, a widget that re-throws
    // every frame would spiral into a rebuild → re-throw → notify loop and
    // freeze the app. The value must be live immediately; the notification must
    // be deferred and coalesced.

    test('value is synchronous, listener callback is deferred', () async {
      final store = DevtrayLog.instance;
      var notified = 0;
      void listener() => notified++;
      store.unseenErrorCount.addListener(listener);
      addTearDown(() => store.unseenErrorCount.removeListener(listener));

      store.report('boom');

      // Value updated now...
      expect(store.unseenErrorCount.value, 1);
      // ...but no listener has fired yet (still on this synchronous stack).
      expect(notified, 0);

      await Future<void>.microtask(() {});
      expect(notified, 1);
    });

    test('many reports in one turn collapse into a single notification', () async {
      final store = DevtrayLog.instance;
      var notified = 0;
      void listener() => notified++;
      store.tick.addListener(listener);
      addTearDown(() => store.tick.removeListener(listener));

      for (var i = 0; i < 50; i++) {
        store.report('boom $i');
      }
      expect(store.entries.length, 50); // all recorded synchronously
      expect(notified, 0); // none delivered yet

      await Future<void>.microtask(() {});
      expect(notified, 1); // 50 reports → one listener callback
    });

    testWidgets('reporting from inside build does not re-enter or throw', (tester) async {
      // A widget that reports an error every time it builds — the exact shape
      // that used to freeze. It must build cleanly and settle.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              DevtrayLog.instance.report('reported during build');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(DevtrayLog.instance.entries, isNotEmpty);
    });
  });

  group('debugLog (the dart:developer drop-in)', () {
    // developer.log is `external` — no hook can capture it, so this bridge is
    // the only way those lines reach the store. It must mirror the real
    // signature, or swapping the import stops being a drop-in.

    test('records into the store, mapping severity and name', () {
      debugLog('signed in', level: 800, name: 'auth');

      final entry = DevtrayLog.instance.entries.single;
      expect(entry.message, 'signed in');
      expect(entry.level, LogLevel.info); // 800 = INFO on the logging scale
      expect(entry.tag, 'auth');
    });

    test('an empty name is no tag, not an empty one', () {
      debugLog('no name given');
      expect(DevtrayLog.instance.entries.single.tag, isNull);
    });

    test('carries the error and stack trace through', () {
      final err = StateError('boom');
      final stack = StackTrace.current;
      debugLog('failed', level: 1000, error: err, stackTrace: stack);

      final entry = DevtrayLog.instance.entries.single;
      expect(entry.level, LogLevel.error);
      expect(entry.error, same(err));
      expect(entry.stackTrace, same(stack));
    });

    test('`log` is the same function, so an import swap needs no call-site edit', () {
      expect(log, same(debugLog));
    });
  });

  group('debugLevelFromName', () {
    test('maps the aliases used by logger / logging / talker', () {
      expect(debugLevelFromName('SEVERE'), LogLevel.error);
      expect(debugLevelFromName('wtf'), LogLevel.error);
      expect(debugLevelFromName('warn'), LogLevel.warning);
      expect(debugLevelFromName('info'), LogLevel.info);
      expect(debugLevelFromName('finest'), LogLevel.debug);
      expect(debugLevelFromName('nonsense'), LogLevel.debug);
      expect(debugLevelFromName(null, fallback: LogLevel.info), LogLevel.info);
    });

    test('maps the package:logging numeric scale', () {
      expect(debugLevelFromSeverity(1000), LogLevel.error);
      expect(debugLevelFromSeverity(900), LogLevel.warning);
      expect(debugLevelFromSeverity(800), LogLevel.info);
      expect(debugLevelFromSeverity(500), LogLevel.debug);
    });
  });

  group('errors in the one DevtrayLog', () {
    test('report() records an error-level entry and increments the badge', () {
      final store = DevtrayLog.instance;
      expect(store.unseenErrorCount.value, 0);

      store.report(StateError('boom'), stackTrace: StackTrace.current);

      final entry = store.entries.single;
      expect(entry.title, contains('boom'));
      expect(entry.isError, isTrue);
      expect(entry.source, ErrorSource.reported);
      expect(store.unseenErrorCount.value, 1);
    });

    test('markErrorsSeen clears the badge but keeps the entries', () {
      final store = DevtrayLog.instance;
      store.report('boom');
      store.markErrorsSeen();

      expect(store.unseenErrorCount.value, 0);
      expect(store.entries, hasLength(1));
    });

    test('title is the first line only', () {
      DevtrayLog.instance.report('line one\nline two');
      expect(DevtrayLog.instance.entries.single.title, 'line one');
    });
  });

  group('LogsDebugPage', () {
    testWidgets('renders logs and filters by search', (tester) async {
      DevtrayLog.instance
        ..log('alpha message')
        ..log('beta message');

      await tester.pumpWidget(_host(const LogsDebugPage()));
      await tester.pumpAndSettle();

      expect(find.text('alpha message'), findsOneWidget);
      expect(find.text('beta message'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pumpAndSettle();

      expect(find.text('alpha message'), findsOneWidget);
      expect(find.text('beta message'), findsNothing);
    });

    testWidgets('shows an empty state', (tester) async {
      await tester.pumpWidget(_host(const LogsDebugPage()));
      await tester.pumpAndSettle();
      expect(find.text('No logs captured'), findsOneWidget);
    });
  });

  group('errors in the combined Logs page', () {
    testWidgets('an error shows as a row, expands to its report, and clears the badge', (tester) async {
      DevtrayLog.instance.report(StateError('kaboom'), stackTrace: StackTrace.current);
      expect(DevtrayLog.instance.unseenErrorCount.value, 1);

      await tester.pumpWidget(_host(const LogsDebugPage()));
      await tester.pumpAndSettle();

      // Opening the Logs page marks them seen — that's what drops the badge.
      expect(DevtrayLog.instance.unseenErrorCount.value, 0);
      expect(find.textContaining('kaboom'), findsOneWidget);

      // Expand the error row inline (no separate detail screen anymore).
      await tester.tap(find.textContaining('kaboom'));
      await tester.pumpAndSettle();

      expect(find.text('Exception'), findsOneWidget);
      expect(find.text('Stack Trace'), findsOneWidget);
    });

    testWidgets('shows the empty state when nothing has been captured', (tester) async {
      await tester.pumpWidget(_host(const LogsDebugPage()));
      await tester.pumpAndSettle();
      expect(find.text('No logs captured'), findsOneWidget);
    });
  });

  group('DeviceDebugPage', () {
    testWidgets('renders provider sections plus live screen metrics', (tester) async {
      await tester.pumpWidget(_host(const DeviceDebugPage(
        provider: StaticDeviceInfoProvider([
          DeviceInfoSection('Environment', {'API': 'https://x.test', 'Flavor': 'dev'}),
        ]),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Environment'), findsOneWidget);
      expect(find.text('https://x.test'), findsOneWidget);
      // Screen section is appended by the page itself, not the provider.
      expect(find.text('Screen'), findsOneWidget);
      expect(find.text('Device pixel ratio'), findsOneWidget);
    });

    testWidgets('CompositeDeviceInfoProvider merges providers in order', (tester) async {
      await tester.pumpWidget(_host(const DeviceDebugPage(
        provider: CompositeDeviceInfoProvider([
          StaticDeviceInfoProvider([DeviceInfoSection('First', {'a': '1'})]),
          StaticDeviceInfoProvider([DeviceInfoSection('Second', {'b': '2'})]),
        ]),
      )));
      await tester.pumpAndSettle();

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('Copy all confirms the press, even where the clipboard cannot answer', (tester) async {
      // There is no clipboard handler under flutter_test, so a Clipboard.setData
      // that is awaited before confirming never resolves — and the button sits
      // there pressed but silent. Same on any embedder whose clipboard is slow
      // or missing. The confirmation is driven by the press for that reason;
      // this test is what pins it down.
      await tester.pumpWidget(_host(const DeviceDebugPage(
        provider: StaticDeviceInfoProvider([
          DeviceInfoSection('Environment', {'Flavor': 'dev'}),
        ]),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Copy all'), findsOneWidget);

      await tester.tap(find.text('Copy all'));
      await tester.pump();

      expect(find.text('Copied'), findsOneWidget);

      // ...and it goes back, so the next copy is still offered.
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.text('Copy all'), findsOneWidget);
    });
  });

  group('launcher error badge', () {
    testWidgets('appears on the launcher when an error is unseen', (tester) async {
      await tester.pumpWidget(DevtrayOverlay(
        pages: const [LogsDebugPage()],
        child: const MaterialApp(home: Scaffold(body: Text('app'))),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsNothing);

      DevtrayLog.instance.report('boom');
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });
  });
}
