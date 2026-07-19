import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The case every earlier test missed: entries arriving **while the finger is
/// still down**.
///
/// `tester.drag()` completes the whole gesture before any build runs, so a log
/// arriving "during" it actually arrives after. That gap is why a suite full of
/// passing scroll tests sat alongside a list that visibly refused to stay put:
/// the follow-maintenance callback is queued during a build in which
/// `_following` is still true, and then fires mid-drag and yanks the reader
/// back to the newest entry.
///
/// These use an explicit gesture so logs really do land between moves.
void main() {
  final store = DevtrayLog.instance;

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
              body: SizedBox(height: 300, child: Builder(builder: const LogsDebugPage().build)),
            ),
          ),
        ),
      );

  List<String> visible(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').trim())
      .where((s) => s.startsWith('line ') || s.startsWith('arriving '))
      .toList();

  testWidgets('a drag is not yanked back when entries arrive mid-gesture', (tester) async {
    for (var i = 0; i < 200; i++) {
      store.log('line $i');
    }
    await pumpPage(tester);
    await tester.pump();

    // Finger down, and keep it down while logs stream in.
    final gesture = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
      store.log('arriving $i');
      await tester.pump();
    }

    final duringDrag = visible(tester);
    expect(duringDrag, isNotEmpty, reason: 'the probe must be reading rows');

    // Still mid-gesture: the newest entries must NOT have been scrolled to.
    expect(
      duringDrag.any((m) => m.startsWith('arriving ')),
      isFalse,
      reason: 'arriving entries must not drag the viewport back while the finger is down',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('position holds after the gesture ends, as more entries arrive', (tester) async {
    for (var i = 0; i < 200; i++) {
      store.log('line $i');
    }
    await pumpPage(tester);
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(find.byType(ListView)));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final settled = visible(tester);

    for (var i = 0; i < 10; i++) {
      store.log('arriving $i');
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(visible(tester), settled, reason: 'the reader stays where they stopped');
  });
}
