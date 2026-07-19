import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Network list under load: a scrolled-back reader must keep their place as
/// requests arrive, including once the ring buffer is at its cap.
///
/// Same problem and same shape of fix as the Logs page — see
/// log_scroll_eviction_test.dart for why these assert on the *visible rows*
/// rather than on `controller.offset`. In a list where entries are inserted at
/// the scroll anchor, a constant offset points at different content on every
/// arrival, so an offset assertion passes while the list visibly scrolls.
void main() {
  final store = NetworkLogStore.instance;

  setUp(store.clear);
  tearDown(() => store.maxEntries = 500);

  Future<void> pumpPage(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          home: DevtrayThemeScope(
            theme: const DevtrayTheme(),
            child: Scaffold(
              // Narrow, so this is the list layout rather than the wide
              // master/detail split.
              body: SizedBox(
                width: 400,
                height: 600,
                child: Builder(builder: const NetworkDebugPage().build),
              ),
            ),
          ),
        ),
      );

  void seed(int count, {String path = 'items'}) {
    for (var i = 0; i < count; i++) {
      final e = store.add(method: 'GET', uri: Uri.parse('https://api.example.com/$path/$i'));
      if (e != null) {
        store.complete(e.id, status: NetworkLogStatus.success, statusCode: 200);
      }
    }
  }

  List<String> visible(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').trim())
      .where((s) => s.contains('/items/') || s.contains('/live/'))
      .toList();

  testWidgets('a scrolled-back reader keeps the same rows as requests arrive', (tester) async {
    seed(300);
    await pumpPage(tester);
    await tester.pump();

    // reverse: true — dragging down moves back through history.
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();

    final before = visible(tester);
    expect(before, isNotEmpty, reason: 'the test must actually be reading rows');

    for (var i = 0; i < 15; i++) {
      seed(1, path: 'live');
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(visible(tester), before, reason: 'the request being read must not slide away');
  });

  testWidgets('holds position at the buffer cap, where arrivals also evict', (tester) async {
    store.maxEntries = 200;
    seed(200); // full

    await pumpPage(tester);
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();

    final before = visible(tester);
    final extentBefore = tester.widget<ListView>(find.byType(ListView)).controller!.position.maxScrollExtent;

    for (var i = 0; i < 20; i++) {
      seed(1, path: 'live');
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // The precondition that makes this the hard case: at the cap the content
    // stops growing — one request in, one evicted out — so any correction
    // measured in pixels of growth silently does nothing.
    final extentAfter = tester.widget<ListView>(find.byType(ListView)).controller!.position.maxScrollExtent;
    expect(extentAfter, closeTo(extentBefore, 1.0), reason: 'at the cap the content slides rather than grows');

    expect(visible(tester), before, reason: 'holds even while older requests are being evicted');
  });

  testWidgets('while pinned to the newest, arrivals stay visible', (tester) async {
    seed(100);
    await pumpPage(tester);
    await tester.pump();

    seed(1, path: 'live');
    await tester.pumpAndSettle();

    // Not scrolled away, so the list should still be following.
    expect(find.textContaining('/live/0'), findsOneWidget);
  });

  testWidgets('rows are a fixed extent, so the list can skip laying them out', (tester) async {
    seed(100);
    await pumpPage(tester);
    await tester.pump();

    // itemExtent is what lets the viewport compute scroll geometry
    // arithmetically. Without it, opening a full buffer means laying out every
    // row to find the end.
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.itemExtent, NetworkLogRow.extent);
    expect(list.reverse, isTrue, reason: 'newest at offset 0 keeps open O(viewport)');
  });

  testWidgets('a full buffer renders only the rows on screen', (tester) async {
    seed(500);
    await pumpPage(tester);
    await tester.pump();

    // The guard against a lazy list quietly becoming eager: 500 entries must
    // not mean 500 built rows.
    expect(
      find.byType(NetworkLogRow).evaluate().length,
      lessThan(60),
      reason: 'only the viewport (plus cache extent) should be built',
    );
  });
}
