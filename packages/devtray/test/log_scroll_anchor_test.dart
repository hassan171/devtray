import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Does the *content* stay put when entries arrive?
///
/// Separate from the follow-behaviour tests because it asserts the thing those
/// got wrong. An earlier version checked that `controller.offset` was unchanged
/// and passed — while the list was visibly scrolling. In a `reverse: true`
/// list, offset is measured from index 0 (the newest entry) and arriving
/// entries are inserted at index 0, so a constant offset lands on *different
/// content* every time one arrives.
///
/// The only assertion that means anything here is which rows are on screen.
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

  /// The log messages actually rendered. The message is in a TextSpan, not
  /// Text.data, so both are read.
  List<String> visibleMessages(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').trim())
      .where((s) => s.startsWith('line ') || s.startsWith('arriving '))
      .toList();

  testWidgets('a scrolled-up reader keeps the same lines on screen as entries arrive', (tester) async {
    for (var i = 0; i < 60; i++) {
      store.log('line $i');
    }
    await pumpPage(tester);
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    final before = visibleMessages(tester);
    expect(before, isNotEmpty, reason: 'the probe must actually be reading rows');

    for (var i = 0; i < 10; i++) {
      store.log('arriving $i');
    }
    await tester.pumpAndSettle();

    expect(
      visibleMessages(tester),
      before,
      reason: 'the line being read must not slide away — this is the whole complaint',
    );
  });

  testWidgets('holds position across several separate arrivals', (tester) async {
    for (var i = 0; i < 60; i++) {
      store.log('line $i');
    }
    await pumpPage(tester);
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    final before = visibleMessages(tester);

    // Trickling in, which is how logs actually arrive — each one is its own
    // frame, and each has to be corrected for.
    for (var i = 0; i < 8; i++) {
      store.log('arriving $i');
      await tester.pumpAndSettle();
    }

    expect(visibleMessages(tester), before, reason: 'corrections must not drift over repeated arrivals');
  });

  testWidgets('while following, the newest entry stays in view', (tester) async {
    for (var i = 0; i < 60; i++) {
      store.log('line $i');
    }
    await pumpPage(tester);
    await tester.pump();

    // Not scrolled away — the list should still follow, which is the opposite
    // behaviour and equally important.
    store.log('arriving now');
    await tester.pumpAndSettle();

    expect(find.text('arriving now'), findsOneWidget);
  });
}
