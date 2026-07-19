import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page() => MaterialApp(
      home: DevtrayThemeScope(
        theme: const DevtrayTheme(),
        // Constrained so the list actually overflows and can be scrolled.
        child: Scaffold(
          body: SizedBox(height: 300, child: Builder(builder: const LogsDebugPage().build)),
        ),
      ),
    );

void main() {
  final store = LogStore.instance;

  setUp(() {
    store
      ..clear()
      ..clearContext()
      ..clearEnrichers();
  });

  /// Enough entries to overflow the viewport.
  void seed(int count, {String prefix = 'line'}) {
    for (var i = 0; i < count; i++) {
      store.log('$prefix $i');
    }
  }

  ScrollController controllerOf(WidgetTester tester) => tester.widget<ListView>(find.byType(ListView)).controller!;

  group('following the newest entry', () {
    testWidgets('offers no jump button while pinned to the bottom', (tester) async {
      seed(60);
      await tester.pumpWidget(_page());
      await tester.pump();

      // Following: there is nothing to jump to.
      expect(find.textContaining('new'), findsNothing);
      expect(find.text('Jump to latest'), findsNothing);
    });

    testWidgets('scrolling up stops the list following, and offers a way back', (tester) async {
      seed(60);
      await tester.pumpWidget(_page());
      await tester.pump();

      // reverse: true, so dragging *down* moves back through history.
      await tester.drag(find.byType(ListView), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(find.text('Jump to latest'), findsOneWidget);
    });

    // NOTE: "position is held" is asserted in log_scroll_anchor_test and
    // log_scroll_eviction_test against the *visible rows*, never the offset.
    //
    // An earlier version of this test compared offsets, passed, and was wrong:
    // entries are inserted at index 0, which is the scroll anchor, so a
    // constant offset points at different content on every arrival. Offsets are
    // a property of the geometry — and the geometry changed twice while this
    // was being written. What the reader cares about is which lines are on
    // screen, so that is what the tests assert.

    testWidgets('counts what arrived while scrolled up', (tester) async {
      seed(60);
      await tester.pumpWidget(_page());
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        store.log('arriving $i');
      }
      await tester.pumpAndSettle();

      // "3 new" and "47 new" are different decisions about whether to look now.
      expect(find.text('3 new'), findsOneWidget);
    });

    testWidgets('tapping the button returns to the newest entry and resumes following', (tester) async {
      seed(60);
      await tester.pumpWidget(_page());
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      store.log('a later arrival');
      await tester.pumpAndSettle();

      // The button, not a log row — rows are InkWells too.
      await tester.tap(find.text('1 new'));
      await tester.pumpAndSettle();

      // `reverse: true`, so the newest entry is at offset 0.
      expect(controllerOf(tester).offset, closeTo(0, 1.0), reason: 'back at the newest entry');
      // Following again, so the affordance goes away.
      expect(find.text('Jump to latest'), findsNothing);
      expect(find.text('1 new'), findsNothing);
    });

    testWidgets('scrolling back to the bottom by hand resumes following too', (tester) async {
      seed(60);
      await tester.pumpWidget(_page());
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('Jump to latest'), findsOneWidget);

      // Dragging the other way returns to the newest entry.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      // A console that stops following after you scrolled back is as bad as
      // one that never stops.
      expect(find.text('Jump to latest'), findsNothing);
    });

    testWidgets('while following, new entries stay visible', (tester) async {
      seed(30);
      await tester.pumpWidget(_page());
      await tester.pump();

      store.log('the newest thing');
      await tester.pumpAndSettle();

      expect(find.text('the newest thing'), findsOneWidget);
    });

    testWidgets('a small overscroll does not silently stop following', (tester) async {
      seed(60);
      await tester.pumpWidget(_page());
      await tester.pump();

      // Within the threshold — turning following off here would look like the
      // list had frozen for no reason.
      await tester.drag(find.byType(ListView), const Offset(0, 12));
      await tester.pumpAndSettle();

      expect(find.text('Jump to latest'), findsNothing);
    });
  });
}
