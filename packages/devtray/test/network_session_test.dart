import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkLogEntry _saved(int id, String path) => NetworkLogEntry(
  id: id,
  method: 'GET',
  uri: Uri.parse('https://api.test$path'),
  requestHeaders: const {},
  queryParameters: const {},
  requestBody: null,
  startedAt: DateTime(2026, 7, 22, 14, 30),
  fields: const {'screen': 'checkout'},
)
  ..statusCode = 200
  ..status = NetworkLogStatus.success
  ..completedAt = DateTime(2026, 7, 22, 14, 30, 1);

/// An in-memory stand-in for the file-backed source.
class _FakeSessions extends NetworkSessionSource {
  final Map<String, List<NetworkLogEntry>> runs;
  _FakeSessions(this.runs);

  @override
  Future<List<NetworkSessionInfo>> list() async => [
    for (final e in runs.entries)
      NetworkSessionInfo(id: e.key, label: e.key, detail: '${e.value.length} requests'),
  ];

  @override
  Future<List<NetworkLogEntry>> load(NetworkSessionInfo session) async => runs[session.id] ?? const [];
}

Widget _page({NetworkSessionSource? source}) => MaterialApp(
  home: Scaffold(
    body: Builder(builder: NetworkDebugPage(sessionSource: source).build),
  ),
);

void main() {
  setUp(() {
    Devtray.reset();
    DevtrayNet.instance
      ..clear()
      ..excludedUrlPatterns.clear();
    DevtrayLog.instance.clear();
  });

  testWidgets('no picker button when no source is supplied', (tester) async {
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();

    // An app with no network persistence shouldn't be offered a browser for
    // files that don't exist.
    expect(find.byTooltip('Load a saved session'), findsNothing);
  });

  testWidgets('the picker opens a saved run into the request list', (tester) async {
    final source = _FakeSessions({
      'run-a': [_saved(1, '/orders'), _saved(2, '/users')],
    });

    // A live request, so we can tell the two apart.
    final live = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/live'))!;
    DevtrayNet.instance.complete(live.id, status: NetworkLogStatus.success, statusCode: 200);

    await tester.pumpWidget(_page(source: source));
    await tester.pumpAndSettle();
    expect(find.textContaining('/live'), findsWidgets);

    await tester.tap(find.byTooltip('Load a saved session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('run-a'));
    await tester.pumpAndSettle();

    // The saved run stands in for the live store: same rows, same detail pane.
    expect(find.textContaining('/orders'), findsWidgets);
    expect(find.textContaining('/live'), findsNothing);
  });

  testWidgets('a loaded run is unmistakably not live, and returns', (tester) async {
    final source = _FakeSessions({'run-a': [_saved(1, '/orders')]});

    await tester.pumpWidget(_page(source: source));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Load a saved session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('run-a'));
    await tester.pumpAndSettle();

    // The one thing that must never be ambiguous.
    expect(find.text('Saved session — not live'), findsOneWidget);
    expect(find.textContaining('1 request'), findsOneWidget);

    // And clearing is not offered: it would either do nothing or delete a file
    // from behind a button that doesn't say so.
    expect(find.byTooltip('Clear all requests'), findsNothing);

    await tester.tap(find.text('Live'));
    await tester.pumpAndSettle();

    expect(find.text('Saved session — not live'), findsNothing);
    expect(find.byTooltip('Clear all requests'), findsOneWidget);
  });

  testWidgets('a request from a saved run opens its detail', (tester) async {
    final source = _FakeSessions({'run-a': [_saved(1, '/orders')]});

    await tester.pumpWidget(_page(source: source));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Load a saved session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('run-a'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NetworkLogRow).first);
    await tester.pumpAndSettle();

    // Selection resolves against the loaded list, not the live store — where
    // the id would find nothing.
    expect(find.text('Context'), findsOneWidget);
  });
}
