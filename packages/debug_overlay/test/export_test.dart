import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(DebugPage page) => MaterialApp(
      home: Scaffold(body: DebugToolsScreen(pages: [page])),
    );

/// Seeds every store, including headers and bodies that a redacting tool would
/// have scrubbed. This one doesn't — the report is for you, and a report you
/// can't replay a request from is useless.
void _seedStores() {
  final logs = NetworkLogStore.instance;
  final entry = logs.add(
    method: 'POST',
    uri: Uri.parse('https://api.test/login'),
    requestHeaders: {'Authorization': 'Bearer live-token', 'Content-Type': 'application/json'},
    requestBody: {'email': 'a@b.c', 'password': 'hunter2'},
  )!;
  logs.complete(
    entry.id,
    status: NetworkLogStatus.success,
    statusCode: 200,
    responseHeaders: {
      'set-cookie': ['session=deadbeef'],
    },
    responseBody: {'access_token': 'issued-token', 'user': 'ada'},
  );

  LogStore.instance.log('Signed in', level: LogLevel.info, tag: 'auth');
  LogStore.instance.report(StateError('boom'), stackTrace: StackTrace.current);
}

void main() {
  setUp(() {
    NetworkLogStore.instance.clear();
    LogStore.instance.clear();
    LogStore.instance.clear();
  });

  group('DebugReport', () {
    test('bundles every section', () {
      _seedStores();

      final report = DebugReport.build(
        deviceInfo: {
          'App': {'Version': '1.2.3'},
        },
      );

      expect(report, contains('# Debug report'));
      expect(report, contains('## Device'));
      expect(report, contains('## Errors'));
      expect(report, contains('## Network'));
      expect(report, contains('## Logs'));

      expect(report, contains('1.2.3'));
      expect(report, contains('POST https://api.test/login'));
      expect(report, contains('boom'));
      expect(report, contains('Signed in'));
    });

    test('captures headers and bodies verbatim — nothing is scrubbed', () {
      _seedStores();

      final report = DebugReport.build();

      // The report has to be complete enough to diagnose from and replay.
      expect(report, contains('Bearer live-token'));
      expect(report, contains('hunter2'));
      expect(report, contains('deadbeef'));
      expect(report, contains('issued-token'));
      expect(report, contains('a@b.c'));
    });

    test('sections can be excluded', () {
      _seedStores();

      final report = DebugReport.build(
        sections: const DebugReportSections(network: false, logs: false),
      );

      expect(report, contains('## Errors'));
      expect(report, isNot(contains('## Network')));
      expect(report, isNot(contains('## Logs')));
    });

    test('empty stores produce a valid, honest report', () {
      final report = DebugReport.build();

      expect(report, contains('## Errors (0)'));
      expect(report, contains('None.'));
    });

    test('caps how much it dumps, but is honest about the total', () {
      for (var i = 0; i < 30; i++) {
        LogStore.instance.log('line $i');
      }

      final report = DebugReport.build(maxLogEntries: 5);

      expect(report, contains('## Logs (30)')); // the real count
      expect(report, contains('line 29')); // newest kept
      expect(report, isNot(contains('line 24'))); // older dropped
    });
  });

  group('ExportDebugPage', () {
    testWidgets('previews the report — nobody should share a blob unseen', (tester) async {
      _seedStores();

      await tester.pumpWidget(_host(const ExportDebugPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('# Debug report'), findsOneWidget);
      expect(find.textContaining('characters'), findsOneWidget);
    });

    testWidgets('deselecting a section drops it from the report', (tester) async {
      _seedStores();

      await tester.pumpWidget(_host(const ExportDebugPage()));
      await tester.pumpAndSettle();

      expect(find.textContaining('## Network'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Network'));
      await tester.pumpAndSettle();

      expect(find.textContaining('## Network'), findsNothing);
    });

    testWidgets('no Share button unless an onShare hook is given', (tester) async {
      await tester.pumpWidget(_host(const ExportDebugPage()));
      await tester.pumpAndSettle();

      // The package takes no share_plus dependency — sharing is the host's call.
      expect(find.text('Share'), findsNothing);
      expect(find.byTooltip('Copy report'), findsOneWidget);
    });

    testWidgets('the Share hook receives the full report', (tester) async {
      _seedStores();
      String? shared;

      await tester.pumpWidget(_host(ExportDebugPage(
        onShare: (report) async => shared = report,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(shared, contains('# Debug report'));
      expect(shared, contains('Bearer live-token'));
    });
  });
}
