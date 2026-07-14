import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hz_toast/hz_toast.dart';

/// Runs [body], then restores the `debugPrint` global that `runDebugApp` hooks.
///
/// flutter_test asserts that a test leaves foundation globals untouched, and it
/// checks *before* tearDown runs — so the restore has to happen inside the test
/// body, not after it.
Future<void> withDebugPrintRestored(Future<void> Function() body) async {
  final original = debugPrint;
  try {
    await body();
  } finally {
    stopCapturingDebugPrint();
    debugPrint = original;
  }
}

const _app = MaterialApp(home: Scaffold(body: Text('app')));

void main() {
  setUp(() {
    LogStore.instance.clear();
    ErrorStore.instance.clear();
  });

  group('runDebugApp', () {
    testWidgets('mounts the app under a DebugOverlay with the launcher', (tester) async {
      await withDebugPrintRestored(() async {
        runDebugApp(_app, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        expect(find.text('app'), findsOneWidget);
        expect(find.byType(DebugOverlay), findsOneWidget);
        expect(find.byIcon(Icons.bug_report), findsOneWidget);
      });
    });

    testWidgets('opens the tools from the launcher', (tester) async {
      await withDebugPrintRestored(() async {
        runDebugApp(_app, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.bug_report));
        await tester.pumpAndSettle();

        expect(find.byType(DebugToolsScreen), findsOneWidget);
        expect(find.text('Logs'), findsOneWidget);
      });
    });

    testWidgets('installs the capture hooks — debugPrint reaches the Logs page', (tester) async {
      await withDebugPrintRestored(() async {
        runDebugApp(_app, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        debugPrint('hello from the app');

        expect(LogStore.instance.entries.any((e) => e.message == 'hello from the app'), isTrue);
      });
    });

    testWidgets('enabled: false is a plain runApp — no overlay in the tree at all', (tester) async {
      await withDebugPrintRestored(() async {
        runDebugApp(_app, enabled: false, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        expect(find.text('app'), findsOneWidget);
        // Not merely inert — absent. A release build gets the app it would have
        // had without the package.
        expect(find.byType(DebugOverlay), findsNothing);
        expect(find.byIcon(Icons.bug_report), findsNothing);

        // And the hooks are not installed either.
        debugPrint('should not be captured');
        expect(LogStore.instance.entries, isEmpty);
      });
    });

    testWidgets('forwards the controller, so open() works from the app', (tester) async {
      await withDebugPrintRestored(() async {
        final controller = DebugOverlayController(showLauncher: false);
        runDebugApp(_app, controller: controller, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.bug_report), findsNothing);

        controller.open();
        await tester.pumpAndSettle();

        expect(find.byType(DebugToolsScreen), findsOneWidget);
      });
    });

    testWidgets('toasts render with no HzToast setup in the host app', (tester) async {
      await withDebugPrintRestored(() async {
        // The app below wires up NOTHING — no HzToastInitializer. The overlay
        // installs one inside its own panel, so the host app stays clean. This
        // is what the copy buttons rely on.
        runDebugApp(_app, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.bug_report));
        await tester.pumpAndSettle();

        expect(find.byType(HzToastInitializer), findsOneWidget);

        // Raised the same way the copy buttons raise it. (Tapping a real copy
        // button can't be used here: it awaits Clipboard.setData first, and the
        // clipboard platform channel has no handler under flutter_test.)
        showDebugToast('Logs copied');

        // Fixed pumps, not pumpAndSettle — the toast animates on a loop and
        // never settles, so pumpAndSettle would time out.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.textContaining('copied'), findsOneWidget);

        // Clear it, so a live toast timer can't leak into the next test.
        HzToast.clearAll();
        await tester.pump(const Duration(seconds: 5));
      });
    });

    testWidgets('forwards presentation and theme', (tester) async {
      await withDebugPrintRestored(() async {
        runDebugApp(
          _app,
          presentation: DebugOverlayPresentation.fullscreen,
          theme: const DebugOverlayTheme.dark(),
          pages: const [LogsDebugPage()],
        );
        await tester.pumpAndSettle();

        final overlay = tester.widget<DebugOverlay>(find.byType(DebugOverlay));
        expect(overlay.presentation, DebugOverlayPresentation.fullscreen);
        expect(overlay.theme.background, const DebugOverlayTheme.dark().background);
      });
    });
  });
}
