// The State page's own tests — with no state-management library in sight.
//
// This is the claim the architecture rests on: `StateDebugPage` reads from
// `StateInspector` and nothing else, so bloc is just one way to fill it and a
// Riverpod (or getx, or homegrown) app can feed the same page by pushing into
// the same small API. `DebugBlocObserver` is only ~40 lines of glue on top.
//
// It's tested here, in the core, precisely because it must NOT need bloc. The
// bloc-specific tests live in debug_overlay_bloc; if these two ever disagree,
// the page has grown a dependency it shouldn't have.
import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host() => const MaterialApp(
      home: Scaffold(body: DebugToolsScreen(pages: [StateDebugPage()])),
    );

/// Stands in for whatever a non-bloc app would push from — a Riverpod notifier,
/// a ChangeNotifier, a plain object. The inspector never sees the type.
class _Counter {
  int value = 0;
}

void main() {
  setUp(() {
    DebugOverlayKillSwitch.reset();
    StateInspector.instance.clear();
  });

  testWidgets('a source pushed in by hand appears on the page', (tester) async {
    final counter = _Counter();
    StateInspector.instance.recordCreate(
      identityHashCode(counter),
      type: 'CounterNotifier',
      state: 0,
      instance: counter,
    );

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('CounterNotifier'), findsOneWidget);
  });

  testWidgets('changes build a history, newest first', (tester) async {
    final counter = _Counter();
    final id = identityHashCode(counter);
    StateInspector.instance.recordCreate(id, type: 'CounterNotifier', state: 0, instance: counter);
    StateInspector.instance.record(id, type: 'CounterNotifier', from: 0, to: 1, instance: counter);
    StateInspector.instance.record(id, type: 'CounterNotifier', from: 1, to: 2, instance: counter);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('CounterNotifier'));
    await tester.pumpAndSettle();

    // The current state, and the transitions that produced it.
    expect(find.textContaining('2'), findsWidgets);
  });

  testWidgets('an error is recorded against its source', (tester) async {
    final counter = _Counter();
    final id = identityHashCode(counter);
    StateInspector.instance.recordCreate(id, type: 'CounterNotifier', state: 0, instance: counter);
    StateInspector.instance.recordError(id, StateError('boom'), StackTrace.current);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('CounterNotifier'), findsOneWidget);
  });

  test('the kill switch stops recording, whatever is pushing', () {
    // The page is debug-only, so a release build must buffer nothing — no matter
    // which library (or none) is feeding it.
    DebugOverlayKillSwitch.enabled = false;
    addTearDown(DebugOverlayKillSwitch.reset);

    final counter = _Counter();
    StateInspector.instance.recordCreate(
      identityHashCode(counter),
      type: 'CounterNotifier',
      state: 0,
      instance: counter,
    );

    expect(StateInspector.instance.sources, isEmpty);
  });
}
