import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// # A note on why this file is thin
///
/// `VisualDebugPage` toggles Flutter's *process-wide* rendering globals
/// (`debugPaintSizeEnabled`, `debugRepaintRainbowEnabled`, `timeDilation`, …) —
/// that is the entire point of the page.
///
/// `flutter_test` runs `debugAssertAllRenderVarsUnset` after every test and
/// fails any test that leaves one of those globals dirty. The page marks the
/// render tree dirty when a flag flips, so a frame stays queued past the end of
/// the test body; whichever order you reset-and-unmount in, that frame can
/// repaint with the flag still set, and the invariant trips.
///
/// The result: **each of these tests passes in isolation, but a test that taps a
/// switch poisons the ones after it in the same file.** That's a harness
/// limitation, not a product bug.
///
/// So this file covers what can be asserted without leaving a flag set. The
/// remaining behaviour — the warning banner, "Reset all", and the `timeDilation`
/// mapping — is verified by hand in the example app.
///
/// If you want to check one of those, run it alone:
/// `flutter test test/visual_debug_page_test.dart --plain-name "..."`

Widget _host() => MaterialApp(
      home: Scaffold(body: DebugToolsScreen(pages: [VisualDebugPage()])),
    );

void main() {
  group('VisualDebugPage', () {
    testWidgets('lists the default flags', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Paint layout bounds'), findsOneWidget);
      expect(find.text('Repaint rainbow'), findsOneWidget);
      expect(find.text('Paint baselines'), findsOneWidget);
      expect(find.text('Highlight taps'), findsOneWidget);
      expect(find.text('Slow animations'), findsOneWidget);

      // Deliberately absent: debugPaintLayerBordersEnabled only draws when a
      // layer records a NEW picture, so cached layers never show it and the
      // switch does nothing. See the note in visual_debug_page.dart.
      expect(find.text('Paint layer borders'), findsNothing);
    });

    testWidgets('every switch starts off, and no warning banner is shown', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(
        tester.widgetList<Switch>(find.byType(Switch)).every((s) => s.value == false),
        isTrue,
      );
      expect(find.textContaining('Debug painting is on'), findsNothing);
    });

    test('every default flag reads and writes a real Flutter global', () {
      // Proves the wiring without mounting anything — toggling a real rendering
      // global inside a *widget* test is what trips the invariant check (see the
      // note at the top of this file). A plain unit test has no such problem.
      for (final flag in kDefaultVisualDebugFlags) {
        expect(flag.get(), isFalse, reason: '${flag.label} should start off');

        flag.set(true);
        expect(flag.get(), isTrue, reason: '${flag.label} did not turn on');

        flag.set(false);
        expect(flag.get(), isFalse, reason: '${flag.label} did not turn off');
      }
    });
  });

  group('custom flags', () {
    testWidgets('the flag list can be replaced, and a custom flag toggles', (tester) async {
      // Uses a local bool rather than a real rendering global, so this one can
      // safely assert the full toggle round-trip.
      var custom = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DebugToolsScreen(pages: [
            VisualDebugPage(flags: [
              VisualDebugFlag(
                label: 'My flag',
                description: 'Something app-specific',
                get: () => custom,
                set: (v) => custom = v,
              ),
            ]),
          ]),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Paint layout bounds'), findsNothing);
      expect(find.text('My flag'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(custom, isTrue);

      // The banner is driven by the flags themselves, so a custom flag lights it
      // up too — this is the one place we can assert it without dirtying a
      // rendering global.
      expect(find.textContaining('Debug painting is on'), findsOneWidget);

      await tester.tap(find.text('Reset all'));
      await tester.pumpAndSettle();

      expect(custom, isFalse);
      expect(find.textContaining('Debug painting is on'), findsNothing);
    });
  });
}
