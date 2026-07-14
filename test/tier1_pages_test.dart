import 'package:debug_overlay/debug_overlay.dart';
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
    LogStore.instance.clear();
    ErrorStore.instance.clear();
  });

  group('LogStore', () {
    test('records, caps, and exposes tags', () {
      final store = LogStore.instance;
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

      expect(LogStore.instance.entries.single.message, 'hello');
      // Observed, not swallowed — the original handler still ran.
      expect(printed, ['hello']);
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

  group('ErrorStore', () {
    test('report() records and increments the unseen badge', () {
      final store = ErrorStore.instance;
      expect(store.unseenCount.value, 0);

      store.report(StateError('boom'), stackTrace: StackTrace.current);

      expect(store.entries.single.title, contains('boom'));
      expect(store.entries.single.source, ErrorSource.manual);
      expect(store.unseenCount.value, 1);
    });

    test('markAllSeen clears the badge but keeps the entries', () {
      final store = ErrorStore.instance;
      store.report('boom');
      store.markAllSeen();

      expect(store.unseenCount.value, 0);
      expect(store.entries, hasLength(1));
    });

    test('title is the first line only', () {
      ErrorStore.instance.report('line one\nline two');
      expect(ErrorStore.instance.entries.single.title, 'line one');
    });
  });

  group('LogsDebugPage', () {
    testWidgets('renders logs and filters by search', (tester) async {
      LogStore.instance
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

    testWidgets('filters by level chip', (tester) async {
      LogStore.instance
        ..log('a debug line')
        ..log('an error line', level: LogLevel.error);

      await tester.pumpWidget(_host(const LogsDebugPage()));
      await tester.pumpAndSettle();

      // Both visible with no filter active.
      expect(find.text('a debug line'), findsOneWidget);
      expect(find.text('an error line'), findsOneWidget);

      // "ERR" also appears as the level badge on the error row — target the chip.
      await tester.tap(find.descendant(of: find.byType(DebugFilterChips<LogLevel>), matching: find.text('ERR')));
      await tester.pumpAndSettle();

      expect(find.text('a debug line'), findsNothing);
      expect(find.text('an error line'), findsOneWidget);
    });

    testWidgets('shows an empty state', (tester) async {
      await tester.pumpWidget(_host(const LogsDebugPage()));
      await tester.pumpAndSettle();
      expect(find.text('No logs yet'), findsOneWidget);
    });
  });

  group('ErrorsDebugPage', () {
    testWidgets('lists errors, opens the detail, and clears the badge', (tester) async {
      ErrorStore.instance.report(StateError('kaboom'), stackTrace: StackTrace.current);
      expect(ErrorStore.instance.unseenCount.value, 1);

      await tester.pumpWidget(_host(const ErrorsDebugPage()));
      await tester.pumpAndSettle();

      // Opening the page marks them seen — that's what drops the launcher badge.
      expect(ErrorStore.instance.unseenCount.value, 0);
      expect(find.textContaining('kaboom'), findsOneWidget);

      await tester.tap(find.textContaining('kaboom'));
      await tester.pumpAndSettle();

      expect(find.text('Stack Trace'), findsOneWidget);
      expect(find.text('Exception'), findsOneWidget);
    });

    testWidgets('shows a reassuring empty state', (tester) async {
      await tester.pumpWidget(_host(const ErrorsDebugPage()));
      await tester.pumpAndSettle();
      expect(find.text('No errors'), findsOneWidget);
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
  });

  group('launcher error badge', () {
    testWidgets('appears on the launcher when an error is unseen', (tester) async {
      await tester.pumpWidget(DebugOverlay(
        pages: const [ErrorsDebugPage()],
        child: const MaterialApp(home: Scaffold(body: Text('app'))),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsNothing);

      ErrorStore.instance.report('boom');
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });
  });
}
