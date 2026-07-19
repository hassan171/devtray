import 'package:bloc/bloc.dart';
import 'package:devtray/devtray.dart';
import 'package:devtray_bloc/devtray_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  /// Not in the state — a plain field, invisible to BlocObserver.
  String? extra;

  void increment() => emit(state + 1);
  void boom() => addError(StateError('boom'), StackTrace.current);
}

/// Exposes its fields from the inside, via the interface.
class InspectableCubit extends Cubit<int> implements DebugInspectable {
  InspectableCubit() : super(0);

  @override
  Map<String, Object?> get debugFields => {'from': 'the interface'};
}

sealed class CounterEvent {
  const CounterEvent();
}

class Increment extends CounterEvent {
  const Increment();
  @override
  String toString() => 'Increment';
}

class Decrement extends CounterEvent {
  const Decrement();
  @override
  String toString() => 'Decrement';
}

class CounterBloc extends Bloc<CounterEvent, int> {
  CounterBloc() : super(0) {
    on<Increment>((e, emit) => emit(state + 1));
    on<Decrement>((e, emit) => emit(state - 1));
  }
}

Widget _host() => const MaterialApp(
      home: Scaffold(body: DebugToolsScreen(pages: [StateDebugPage()])),
    );

void main() {
  setUp(() {
    DevtrayKillSwitch.reset();
    DevtrayState.instance.clear();
    Bloc.observer = DebugBlocObserver();
  });

  tearDown(() {
    Bloc.observer = _NoopObserver();
    DevtrayKillSwitch.reset();
  });

  group('tracking', () {
    test('a cubit is tracked from creation, with its initial state', () {
      final cubit = CounterCubit();
      addTearDown(cubit.close);

      final tracked = DevtrayState.instance.sources.single;
      expect(tracked.type, 'CounterCubit');
      expect(tracked.state, 0);
      expect(tracked.changes, isEmpty, reason: 'creation is not a change');
    });

    test('emits are recorded, newest first', () {
      final cubit = CounterCubit();
      addTearDown(cubit.close);

      cubit
        ..increment()
        ..increment();

      final tracked = DevtrayState.instance.sources.single;
      expect(tracked.state, 2);
      expect(tracked.changes, hasLength(2));

      // Newest first.
      expect(tracked.changes[0].from, 1);
      expect(tracked.changes[0].to, 2);
      expect(tracked.changes[1].from, 0);
      expect(tracked.changes[1].to, 1);
    });

    test('two instances of the same cubit are NOT conflated', () {
      // An app can have several instances of one cubit alive at once — one per
      // screen. Tracking by type would merge them.
      final a = CounterCubit();
      final b = CounterCubit();
      addTearDown(a.close);
      addTearDown(b.close);

      a.increment();

      final sources = DevtrayState.instance.sources;
      expect(sources, hasLength(2));
      expect(sources.map((x) => x.state), containsAll([1, 0]));
    });

    test('errors are captured', () {
      final cubit = CounterCubit();
      addTearDown(cubit.close);

      cubit.boom();

      final tracked = DevtrayState.instance.sources.single;
      expect(tracked.error, isA<StateError>());
      expect(tracked.stackTrace, isNotNull);
    });

    test('a closed cubit is kept, but marked', () async {
      final cubit = CounterCubit();
      cubit.increment();
      await cubit.close();

      final tracked = DevtrayState.instance.sources.single;
      // You often want to see what a cubit did just before its screen was popped.
      expect(tracked.isClosed, isTrue);
      expect(tracked.state, 1);
      expect(tracked.changes, hasLength(1));
    });

    test('live cubits sort before closed ones', () async {
      final closed = CounterCubit();
      await closed.close();

      final live = CounterCubit();
      addTearDown(live.close);

      expect(DevtrayState.instance.sources.first.isClosed, isFalse);
      expect(DevtrayState.instance.sources.last.isClosed, isTrue);
    });

    test('clearClosed drops the dead ones and keeps the live', () async {
      final closed = CounterCubit();
      await closed.close();
      final live = CounterCubit();
      addTearDown(live.close);

      DevtrayState.instance.clearClosed();

      expect(DevtrayState.instance.sources.single.isClosed, isFalse);
    });
  });

  group('events — the ordering trap', () {
    // A Bloc calls onTransition and THEN emit (which fires onChange) — see
    // Bloc._on's onEmit. So the event arrives BEFORE the change it caused.
    // Assuming the reverse staples each event onto the *previous* change.

    test('each change carries the event that actually caused it', () async {
      final bloc = CounterBloc();
      addTearDown(bloc.close);

      bloc.add(const Increment());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const Decrement());
      await Future<void>.delayed(Duration.zero);

      final tracked = DevtrayState.instance.sources.single;
      expect(tracked.changes, hasLength(2));

      // Newest first: the Decrement (1 → 0) and the Increment (0 → 1).
      expect(tracked.changes[0].event, isA<Decrement>());
      expect(tracked.changes[0].from, 1);
      expect(tracked.changes[0].to, 0);

      expect(tracked.changes[1].event, isA<Increment>());
      expect(tracked.changes[1].from, 0);
      expect(tracked.changes[1].to, 1);
    });

    test('a bloc change is recorded ONCE, not twice', () async {
      // onTransition and onChange both fire for the same state change. Recording
      // in both would double-log every change.
      final bloc = CounterBloc();
      addTearDown(bloc.close);

      bloc.add(const Increment());
      await Future<void>.delayed(Duration.zero);

      expect(DevtrayState.instance.sources.single.changes, hasLength(1));
    });

    test('a plain cubit has no event', () {
      final cubit = CounterCubit();
      addTearDown(cubit.close);

      cubit.increment();

      expect(DevtrayState.instance.sources.single.changes.single.event, isNull);
    });
  });

  group('fields outside the state', () {
    // The inspector only ever sees the current state. Anything else a cubit holds
    // — a sync queue, a lookup map, a counter — is invisible to it, and Flutter
    // has no reflection to go find it. So the cubit (or the app) has to point.

    test('inspect() exposes fields without touching the cubit', () {
      DevtrayState.instance.inspect<CounterCubit>((c) => {'extra': c.extra});
      addTearDown(DevtrayState.instance.clearInspectors);

      final cubit = CounterCubit();
      addTearDown(cubit.close);
      cubit.extra = 'hello';

      final tracked = DevtrayState.instance.sources.single;
      expect(DevtrayState.instance.liveFieldsOf(tracked), {'extra': 'hello'});
    });

    test('fields are read LIVE, not snapshotted at emit time', () {
      DevtrayState.instance.inspect<CounterCubit>((c) => {'extra': c.extra});
      addTearDown(DevtrayState.instance.clearInspectors);

      final cubit = CounterCubit();
      addTearDown(cubit.close);

      final tracked = DevtrayState.instance.sources.single;
      expect(DevtrayState.instance.liveFieldsOf(tracked)['extra'], isNull);

      // Changed with NO emit — the whole reason the detail pane has a re-read
      // button.
      cubit.extra = 'changed';

      expect(DevtrayState.instance.liveFieldsOf(tracked)['extra'], 'changed');
    });

    test('DebugInspectable works too', () {
      final cubit = InspectableCubit();
      addTearDown(cubit.close);

      final tracked = DevtrayState.instance.sources.single;
      expect(DevtrayState.instance.liveFieldsOf(tracked), {'from': 'the interface'});
    });

    test('a registration WINS over the interface, so you can override a cubit', () {
      DevtrayState.instance.inspect<InspectableCubit>((c) => {'from': 'the registry'});
      addTearDown(DevtrayState.instance.clearInspectors);

      final cubit = InspectableCubit();
      addTearDown(cubit.close);

      final tracked = DevtrayState.instance.sources.single;
      expect(DevtrayState.instance.liveFieldsOf(tracked), {'from': 'the registry'});
    });

    test('a cubit exposing nothing yields no fields', () {
      final cubit = CounterCubit();
      addTearDown(cubit.close);

      expect(DevtrayState.instance.liveFieldsOf(DevtrayState.instance.sources.single), isEmpty);
    });

    test('a throwing extractor does NOT take the page down', () {
      DevtrayState.instance.inspect<CounterCubit>((c) => throw StateError('bad extractor'));
      addTearDown(DevtrayState.instance.clearInspectors);

      final cubit = CounterCubit();
      addTearDown(cubit.close);

      final fields = DevtrayState.instance.liveFieldsOf(DevtrayState.instance.sources.single);
      expect(fields.keys.single, contains('threw'));
      expect(fields.values.single.toString(), contains('bad extractor'));
    });

    test('the instance is held WEAKLY — the tool must not keep your cubits alive', () {
      final cubit = CounterCubit();
      final tracked = DevtrayState.instance.sources.single;

      // A strong reference would make this debug tool the thing leaking every
      // cubit the app ever created — the exact bug it exists to help you find.
      expect(tracked.ref, isNotNull);
      expect(tracked.ref!.target, same(cubit));

      cubit.close();
    });
  });

  group('caps', () {
    test('changes are capped per source, keeping the newest', () {
      DevtrayState.instance.maxChangesPerSource = 3;
      addTearDown(() => DevtrayState.instance.maxChangesPerSource = 100);

      final cubit = CounterCubit();
      addTearDown(cubit.close);

      for (var i = 0; i < 10; i++) {
        cubit.increment();
      }

      final changes = DevtrayState.instance.sources.single.changes;
      expect(changes, hasLength(3));
      expect(changes.first.to, 10, reason: 'the newest is kept');
    });
  });

  group('display / format', () {
    test('a registered formatter renders the state', () {
      DevtrayState.instance.format<int>((n) => 'count=$n');
      addTearDown(DevtrayState.instance.clearInspectors);

      expect(DevtrayState.instance.display(3), 'count=3');
    });

    test('formatSource scopes to one source type, not every state of that type', () {
      DevtrayState.instance.formatSource<CounterCubit>((s) => 'only-counter=$s');
      addTearDown(DevtrayState.instance.clearInspectors);

      // Matches when the source type is passed…
      expect(DevtrayState.instance.display(3, sourceType: 'CounterCubit'), 'only-counter=3');
      // …but a different source with the same int state is untouched.
      expect(DevtrayState.instance.display(3, sourceType: 'OtherCubit'), '3');
      // …and with no source context at all, it doesn't apply.
      expect(DevtrayState.instance.display(3), '3');
    });

    test('formatSource wins over a state-type format', () {
      DevtrayState.instance.format<int>((n) => 'by-type');
      DevtrayState.instance.formatSource<CounterCubit>((s) => 'by-source');
      addTearDown(DevtrayState.instance.clearInspectors);

      expect(DevtrayState.instance.display(1, sourceType: 'CounterCubit'), 'by-source');
      // A source WITHOUT its own formatter still falls back to the state-type one.
      expect(DevtrayState.instance.display(1, sourceType: 'OtherCubit'), 'by-type');
    });

    test('a List pretty-prints by default (no registration)', () {
      final out = DevtrayState.instance.display(['a', 'b']);
      // JSON-indented — one entry per line, not the cramped [a, b].
      expect(out, contains('\n'));
      expect(out, contains('"a"'));
    });

    test('a non-JSON-encodable list lays out element-wise, not one cramped line', () {
      // A list of objects JsonEncoder can't handle must not throw — each element
      // gets its own line via toString().
      final out = DevtrayState.instance.display([CounterCubit(), CounterCubit()]);
      expect(out, contains('CounterCubit'));
      expect(out, contains('\n'), reason: 'one entry per line');
    });

    test('a Set is rendered one entry per line', () {
      final out = DevtrayState.instance.display({'x', 'y'});
      expect(out, contains('"x"'));
      expect(out, contains('\n'));
    });

    test('a Map renders too, and a non-encodable one degrades to key: value', () {
      expect(DevtrayState.instance.display({'a': 1}), contains('"a"'));
      // A value JsonEncoder can't take (a live object) → "key: value" lines,
      // each value via its own toString().
      final out = DevtrayState.instance.display({'c': 'hi', 'n': const Duration(seconds: 1)});
      expect(out, 'c: hi\nn: 0:00:01.000000');
    });

    test('a DateTime uses ISO-8601', () {
      final out = DevtrayState.instance.display(DateTime.utc(2026, 7, 15, 9, 30));
      expect(out, '2026-07-15T09:30:00.000Z');
    });

    test('a throwing formatter degrades instead of taking the page down', () {
      DevtrayState.instance.format<int>((_) => throw StateError('bad'));
      addTearDown(DevtrayState.instance.clearInspectors);

      expect(DevtrayState.instance.display(1), contains('formatter threw'));
    });

    testWidgets('the formatted state shows on the page', (tester) async {
      DevtrayState.instance.format<int>((n) => 'COUNT_$n');
      addTearDown(DevtrayState.instance.clearInspectors);

      final cubit = CounterCubit();
      addTearDown(cubit.close);
      cubit.increment();

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('COUNT_1'), findsOneWidget);
    });
  });

  group('the kill switch', () {
    test('nothing is tracked when it is off', () {
      DevtrayKillSwitch.enabled = false;

      final cubit = CounterCubit();
      addTearDown(cubit.close);
      cubit.increment();

      expect(DevtrayState.instance.sources, isEmpty);
    });
  });

  group('chaining', () {
    test('an existing observer still gets everything', () {
      final seen = <String>[];
      Bloc.observer = DebugBlocObserver(next: _RecordingObserver(seen));

      final cubit = CounterCubit();
      addTearDown(cubit.close);
      cubit.increment();

      // Your own logging keeps working.
      expect(seen, contains('create'));
      expect(seen, contains('change'));
      // …and ours does too.
      expect(DevtrayState.instance.sources.single.changes, hasLength(1));
    });
  });

  group('StateDebugPage', () {
    testWidgets('tells you when no observer is installed', (tester) async {
      Bloc.observer = _NoopObserver();
      DevtrayState.instance.clear();

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // The empty state carries the setup, because a blank page with no
      // observer installed is nearly always a setup problem.
      expect(find.text('No state sources yet'), findsOneWidget);
      expect(find.textContaining('Bloc.observer = DebugBlocObserver()'), findsOneWidget);
    });

    testWidgets('lists cubits with their live state', (tester) async {
      final cubit = CounterCubit();
      addTearDown(cubit.close);
      cubit.increment();

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('CounterCubit'), findsOneWidget);
      expect(find.text('1'), findsWidgets, reason: 'the live state is shown');
    });

    testWidgets('the list updates live as the cubit emits', (tester) async {
      final cubit = CounterCubit();
      addTearDown(cubit.close);

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      cubit.increment();
      await tester.pumpAndSettle();

      // This is the whole point — watching state change on-device.
      expect(DevtrayState.instance.sources.single.state, 1);
      expect(find.text('CounterCubit'), findsOneWidget);
    });

    testWidgets('tapping a source shows its change history', (tester) async {
      final bloc = CounterBloc();
      addTearDown(bloc.close);

      // Dispatch and let the event process INSIDE the tester's async zone. A
      // bare `await Future.delayed(Duration.zero)` here leaves the bloc's event
      // subscription with pending work that later `pump()`s block on — the test
      // then hangs. runAsync drains it against real async before we mount.
      await tester.runAsync(() async {
        bloc.add(const Increment());
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('CounterBloc'));
      await tester.pumpAndSettle();

      expect(find.text('Current state'), findsOneWidget);
      expect(find.text('Changes'), findsOneWidget);

      // The history is shown, not hidden behind a chevron. "What changed just
      // before it broke" is the question this page exists to answer, so the
      // answer shouldn't cost a tap — and the event that caused each change is
      // part of it.
      expect(find.text('Increment'), findsOneWidget);
    });

    testWidgets('search filters by type', (tester) async {
      final cubit = CounterCubit();
      final bloc = CounterBloc();
      addTearDown(cubit.close);
      addTearDown(bloc.close);

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'cubit');
      await tester.pumpAndSettle();

      expect(find.text('CounterCubit'), findsOneWidget);
      expect(find.text('CounterBloc'), findsNothing);
    });

    testWidgets('search also matches the live state, not just the type', (tester) async {
      final cubit = CounterCubit();
      final bloc = CounterBloc();
      addTearDown(cubit.close);
      addTearDown(bloc.close);
      cubit.increment();
      cubit.increment();

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // The state is half of what's on the row — a query that can't reach it
      // looks broken. '2' is the cubit's state and appears in no type name.
      await tester.enterText(find.byType(TextField).first, '2');
      await tester.pumpAndSettle();

      expect(find.text('CounterCubit'), findsOneWidget);
      expect(find.text('CounterBloc'), findsNothing);
    });
  });
}

/// BlocObserver is abstract in bloc 9, so tests need a concrete no-op to reset to.
class _NoopObserver extends BlocObserver {}

class _RecordingObserver extends BlocObserver {
  final List<String> seen;
  _RecordingObserver(this.seen);

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    seen.add('create');
    super.onCreate(bloc);
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    seen.add('change');
    super.onChange(bloc, change);
  }
}
