import 'package:devtray/devtray.dart';
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
    DevtrayLog.instance.clear();
    // Capture and panel state are process-global, so anything a test sets would
    // otherwise leak into every test after it — a hidden launcher being the
    // failure that actually bit.
    Devtray.reset();
  });

  group('runDebugApp', () {
    testWidgets('mounts the app under a DevtrayOverlay with the launcher', (tester) async {
      await withDebugPrintRestored(() async {
        runDebugApp(() => _app, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        expect(find.text('app'), findsOneWidget);
        expect(find.byType(DevtrayOverlay), findsOneWidget);
        expect(find.byIcon(Icons.bug_report), findsOneWidget);
      });
    });

    testWidgets('opens the tools from the launcher', (tester) async {
      await withDebugPrintRestored(() async {
        runDebugApp(() => _app, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.bug_report));
        await tester.pumpAndSettle();

        expect(find.byType(DebugToolsScreen), findsOneWidget);
        expect(find.text('Logs'), findsOneWidget);
      });
    });

    testWidgets('installs the capture hooks — debugPrint reaches the Logs page', (tester) async {
      await withDebugPrintRestored(() async {
        runDebugApp(() => _app, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        debugPrint('hello from the app');

        expect(DevtrayLog.instance.entries.any((e) => e.message == 'hello from the app'), isTrue);
      });
    });

    // There is deliberately no `enabled: false` case here any more.
    //
    // That flag used to make this function a plain `runApp` — no Zone, no hooks,
    // no overlay. It is gone because keeping devtray out of a release build is
    // now the caller's `if`, which is total in a way a flag read *after* the Zone
    // is installed could never be. See the note on runDebugApp.
    testWidgets('capture is inert when Devtray.enabled is false', (tester) async {
      await withDebugPrintRestored(() async {
        Devtray.enabled = false;
        addTearDown(Devtray.reset);

        runDebugApp(() => _app, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        expect(find.text('app'), findsOneWidget);

        // The hooks are installed — that is the trade — but nothing is recorded.
        debugPrint('should not be captured');
        expect(DevtrayLog.instance.entries, isEmpty);
      });
    });

    testWidgets('configure ..launcher(false) is not undone when the overlay mounts', (tester) async {
      await withDebugPrintRestored(() async {
        addTearDown(Devtray.reset);

        runDebugApp(
          () => _app,
          configure: (d) => d..launcher(false),
          pages: const [LogsDebugPage()],
        );
        await tester.pumpAndSettle();

        // The overlay mounts AFTER configure runs and carries its own
        // `showLauncher` default of true. Seeding unconditionally would undo the
        // explicit choice a frame later — silently, and only in the real app,
        // since nothing else reads it back.
        expect(Devtray.showLauncher, isFalse);
        expect(find.byIcon(Icons.bug_report), findsNothing);
      });
    });

    testWidgets('Devtray.open() works from the app, with the launcher hidden', (tester) async {
      await withDebugPrintRestored(() async {
        runDebugApp(() => _app, showLauncher: false, pages: const [LogsDebugPage()]);
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.bug_report), findsNothing);

        Devtray.open();
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

        DevtrayLog.instance.log('a line worth copying');
        runDebugApp(() => _app, pages: const [LogsDebugPage()]);
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
        runDebugApp(() => _app, pages: const [LogsDebugPage()]);
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
          () => _app,
          presentation: DevtrayPresentation.fullscreen,
          theme: const DevtrayTheme.dark(),
          pages: const [LogsDebugPage()],
        );
        await tester.pumpAndSettle();

        final overlay = tester.widget<DevtrayOverlay>(find.byType(DevtrayOverlay));
        expect(overlay.presentation, DevtrayPresentation.fullscreen);
        expect(overlay.theme.background, const DevtrayTheme.dark().background);
      });
    });
  });
}
