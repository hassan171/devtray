import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Holding position when the buffer is **at its cap**.
///
/// Separate from the other scroll tests because it is the case they all missed.
/// Below the cap the content grows as entries arrive, and several plausible
/// fixes appear to work. At the cap it stops growing — one entry in, one
/// evicted out — so `maxScrollExtent` is constant while the content underneath
/// slides by a row per arrival. Any correction measured in *pixels of growth*
/// silently does nothing here; only a row count sees it.
void main() {
  final store = LogStore.instance;

  setUp(() {
    store
      ..clear()
      ..clearContext()
      ..clearEnrichers();
  });

  Future<void> pumpPage(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          home: DevtrayThemeScope(
            theme: const DevtrayTheme(),
            child: Scaffold(
              body: SizedBox(height: 600, child: Builder(builder: const LogsDebugPage().build)),
            ),
          ),
        ),
      );

  List<String> visible(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').trim())
      .where((s) => s.startsWith('line ') || s.startsWith('arriving '))
      .toList();

  testWidgets('the reader holds position while entries evict at the cap', (tester) async {
    store.maxEntries = 400;
    addTearDown(() => store.maxEntries = 1000);

    // Fill to the cap, so every further entry evicts one.
    for (var i = 0; i < 400; i++) {
      store.log('line $i');
    }
    await pumpPage(tester);
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();

    final before = visible(tester);
    expect(before, isNotEmpty, reason: 'the test must actually be reading rows');

    final extentBefore = tester.widget<ListView>(find.byType(ListView)).controller!.position.maxScrollExtent;

    for (var i = 0; i < 15; i++) {
      store.log('arriving $i');
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // The precondition that makes this test worth having: if the extent grew,
    // the buffer wasn't actually at its cap and this is just the easy case.
    final extentAfter = tester.widget<ListView>(find.byType(ListView)).controller!.position.maxScrollExtent;
    expect(
      extentAfter,
      closeTo(extentBefore, 1.0),
      reason: 'at the cap the content slides rather than grows — that is the whole point',
    );

    expect(
      visible(tester),
      before,
      reason: 'the lines being read must not slide away as older ones are evicted',
    );
  });

  testWidgets('holds through a long run of arrivals without drifting', (tester) async {
    store.maxEntries = 300;
    addTearDown(() => store.maxEntries = 1000);

    for (var i = 0; i < 300; i++) {
      store.log('line $i');
    }
    await pumpPage(tester);
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    final before = visible(tester);

    // Many small arrivals: a per-arrival rounding error would accumulate into
    // visible drift over this many frames.
    for (var i = 0; i < 40; i++) {
      store.log('arriving $i');
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(visible(tester), before, reason: 'corrections must not accumulate error');
  });
}
