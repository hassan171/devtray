import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Text fields inside the tools panel need more than a Navigator.
///
/// Typing a character goes through the platform text-input channel and works
/// anywhere. Backspace, the arrow keys and select-all are **key bindings**,
/// resolved by the Shortcuts/Actions pair `WidgetsApp` installs — and the panel
/// is rendered *above* MaterialApp, outside that scope.
///
/// Symptom when it's missing: you can type into a field but you cannot delete a
/// character or move the caret. These tests drive real key events, so they fail
/// if that stack is ever dropped again.
void main() {
  final controller = TextEditingController();

  Widget host() => DevtrayOverlay(
        presentation: DevtrayPresentation.fullscreen,
        pages: [
          DebugPage.builder(
            title: 'Field',
            builder: (_) => TextField(controller: controller),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: Text('app'))),
      );

  /// Opens the panel and focuses the field with some text in it.
  Future<void> openWithText(WidgetTester tester, String text) async {
    final overlay = host();
    await tester.pumpWidget(overlay);

    Devtray.open();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    controller.text = text;
    controller.selection = TextSelection.collapsed(offset: text.length);
    await tester.pump();
  }

  testWidgets('backspace deletes a character', (tester) async {
    await openWithText(tester, 'abc');

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(controller.text, 'ab');
  });

  testWidgets('the arrow keys move the caret', (tester) async {
    await openWithText(tester, 'abc');
    expect(controller.selection.baseOffset, 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.baseOffset, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.baseOffset, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.selection.baseOffset, 2);
  });

  testWidgets('backspace mid-string deletes the right character', (tester) async {
    await openWithText(tester, 'abc');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    // Caret was between 'b' and 'c' — backspace takes the 'b'.
    expect(controller.text, 'ac');
  });

  testWidgets('typing still works', (tester) async {
    await openWithText(tester, 'ab');

    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump();

    expect(controller.text, 'abcd');
  });
}
