import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory [LogSessionSource] — no files, so this runs anywhere.
class _FakeSessions extends LogSessionSource {
  final Map<String, List<LogEntry>> data;
  final bool deletable;
  Object? listError;

  _FakeSessions(this.data, {this.deletable = true});

  @override
  Future<List<LogSessionInfo>> list() async {
    if (listError case final e?) throw e;
    return [
      for (final id in data.keys) LogSessionInfo(id: id, label: id, detail: '${data[id]!.length} entries'),
    ];
  }

  @override
  Future<List<LogEntry>> load(LogSessionInfo session) async => data[session.id] ?? const [];

  @override
  bool get canDelete => deletable;

  @override
  Future<void> delete(LogSessionInfo session) async => data.remove(session.id);

  @override
  Future<void> deleteAll() async => data.clear();
}

LogEntry _entry(String message, {int id = 0}) =>
    LogEntry(id: id, time: DateTime(2026, 7, 19, 14, 30), level: LogLevel.info, message: message);

Widget _wrap(Widget child) => MaterialApp(
      home: DevtrayThemeScope(
        theme: const DevtrayTheme(),
        child: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() => DevtrayLog.instance.clear());

  group('the Logs page without a session source', () {
    testWidgets('shows no session button — nothing to browse', (tester) async {
      await tester.pumpWidget(_wrap(Builder(builder: const LogsDebugPage().build)));
      await tester.pump();

      expect(find.byIcon(Icons.folder_open), findsNothing);
    });
  });

  group('the Logs page with a session source', () {
    testWidgets('offers the picker, and loading one shows its entries', (tester) async {
      final source = _FakeSessions({
        'run-a': [_entry('from the saved run', id: 1)],
      });

      await tester.pumpWidget(_wrap(Builder(builder: LogsDebugPage(sessionSource: source).build)));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      expect(find.text('run-a'), findsOneWidget);

      await tester.tap(find.text('run-a'));
      await tester.pumpAndSettle();

      expect(find.text('from the saved run'), findsOneWidget);
    });

    testWidgets('a loaded session is marked as not live', (tester) async {
      final source = _FakeSessions({
        'run-a': [_entry('historical', id: 1)],
      });

      await tester.pumpWidget(_wrap(Builder(builder: LogsDebugPage(sessionSource: source).build)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      await tester.tap(find.text('run-a'));
      await tester.pumpAndSettle();

      // The whole point of the separate view: a stale session read as live
      // looks exactly like a bug that stopped reproducing.
      expect(find.textContaining('not live'), findsOneWidget);
    });

    testWidgets('a loaded session never mixes into the live buffer', (tester) async {
      DevtrayLog.instance.log('live line');

      final source = _FakeSessions({
        'run-a': [_entry('session line', id: 99)],
      });

      await tester.pumpWidget(_wrap(Builder(builder: LogsDebugPage(sessionSource: source).build)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      await tester.tap(find.text('run-a'));
      await tester.pumpAndSettle();

      expect(
        DevtrayLog.instance.entries.map((e) => e.message),
        isNot(contains('session line')),
        reason: 'a past run must not be re-exported by the sinks as though it were new',
      );
    });

    testWidgets('going back to live restores the live stream', (tester) async {
      DevtrayLog.instance.log('live line');

      final source = _FakeSessions({
        'run-a': [_entry('session line', id: 99)],
      });

      await tester.pumpWidget(_wrap(Builder(builder: LogsDebugPage(sessionSource: source).build)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      await tester.tap(find.text('run-a'));
      await tester.pumpAndSettle();

      expect(find.text('live line'), findsNothing);

      await tester.tap(find.text('Live'));
      await tester.pumpAndSettle();

      expect(find.text('live line'), findsOneWidget);
      expect(find.textContaining('not live'), findsNothing);
    });

    testWidgets('the clear button is hidden while viewing a session', (tester) async {
      final source = _FakeSessions({
        'run-a': [_entry('historical', id: 1)],
      });

      await tester.pumpWidget(_wrap(Builder(builder: LogsDebugPage(sessionSource: source).build)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      await tester.tap(find.text('run-a'));
      await tester.pumpAndSettle();

      // "Clear logs" on a saved run would mean deleting a file from behind a
      // button that means something else everywhere it appears.
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('an empty session says so, without blaming missing capture', (tester) async {
      final source = _FakeSessions({'empty-run': []});

      await tester.pumpWidget(_wrap(Builder(builder: LogsDebugPage(sessionSource: source).build)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      await tester.tap(find.text('empty-run'));
      await tester.pumpAndSettle();

      expect(find.text('This session is empty'), findsOneWidget);
      expect(find.textContaining('runDebugApp'), findsNothing, reason: 'wrong advice — the file simply had nothing in it');
    });
  });

  group('LogSessionPicker', () {
    testWidgets('an empty list explains how sessions get there', (tester) async {
      final source = _FakeSessions({});

      await tester.pumpWidget(_wrap(Builder(builder: LogsDebugPage(sessionSource: source).build)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      expect(find.text('No saved sessions'), findsOneWidget);
      expect(find.textContaining('addSink'), findsOneWidget);
    });

    testWidgets('a source that cannot list reports the failure', (tester) async {
      final source = _FakeSessions({})..listError = StateError('permission denied');

      await tester.pumpWidget(_wrap(Builder(builder: LogsDebugPage(sessionSource: source).build)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      // An error shown as an empty list reads as "nothing was ever saved".
      expect(find.text('Could not read saved sessions'), findsOneWidget);
      expect(find.textContaining('permission denied'), findsOneWidget);
    });

    testWidgets('deleting asks first, then removes the session', (tester) async {
      final source = _FakeSessions({
        'run-a': [_entry('a', id: 1)],
      });

      await tester.pumpWidget(_wrap(Builder(builder: LogsDebugPage(sessionSource: source).build)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: find.byType(LogSessionPicker<LogSessionInfo>), matching: find.byIcon(Icons.delete_outline)));
      await tester.pumpAndSettle();

      expect(find.text('Delete this session?'), findsOneWidget);
      expect(source.data, contains('run-a'), reason: 'not deleted until confirmed');

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(source.data, isEmpty);
      expect(find.text('No saved sessions'), findsOneWidget);
    });

    testWidgets('cancelling a delete keeps the session', (tester) async {
      final source = _FakeSessions({
        'run-a': [_entry('a', id: 1)],
      });

      await tester.pumpWidget(_wrap(Builder(builder: LogsDebugPage(sessionSource: source).build)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(LogSessionPicker<LogSessionInfo>), matching: find.byIcon(Icons.delete_outline)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(source.data, contains('run-a'));
    });

    testWidgets('a read-only source offers no delete controls', (tester) async {
      final source = _FakeSessions({
        'run-a': [_entry('a', id: 1)],
      }, deletable: false);

      await tester.pumpWidget(_wrap(Builder(builder: LogsDebugPage(sessionSource: source).build)));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.folder_open));
      await tester.pumpAndSettle();

      // Scoped to the dialog: the page's own "clear all logs" button uses the
      // same icon, and it is not what this is asserting about.
      expect(
        find.descendant(of: find.byType(LogSessionPicker<LogSessionInfo>), matching: find.byIcon(Icons.delete_outline)),
        findsNothing,
      );
      expect(find.byIcon(Icons.delete_sweep_outlined), findsNothing);
    });
  });
}
