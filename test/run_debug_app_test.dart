import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    LogStore.instance.clear();
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

    testWidgets('copying writes to the clipboard silently, flashing a checkmark', (tester) async {
      await withDebugPrintRestored(() async {
        // flutter_test has no clipboard, so stand one in and record the write.
        String? clipboard;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') clipboard = call.arguments['text'] as String;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );

        LogStore.instance.log('a line worth copying');
        runDebugApp(_app, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.bug_report));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Copy all'));
        await tester.pump();

        expect(clipboard, contains('a line worth copying'));

        // Feedback is the icon itself — nothing overlays the data you're reading,
        // and there's nothing to dismiss.
        expect(find.byIcon(Icons.check), findsOneWidget);

        // …and it reverts on its own.
        await tester.pump(const Duration(milliseconds: 1300));
        expect(find.byIcon(Icons.check), findsNothing);
        expect(find.byIcon(Icons.copy_all), findsOneWidget);
      });
    });

    testWidgets('a copy button with nothing to copy is disabled', (tester) async {
      await withDebugPrintRestored(() async {
        // No logs — so "Copy all" has nothing to write.
        runDebugApp(_app, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.bug_report));
        await tester.pumpAndSettle();

        final button = tester.widget<IconButton>(
          find.ancestor(of: find.byIcon(Icons.copy_all), matching: find.byType(IconButton)),
        );
        expect(button.onPressed, isNull);
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
