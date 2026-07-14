import 'package:bloc/bloc.dart';
import 'package:debug_overlay/debug_overlay.dart';
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
      home: Scaffold(body: DebugToolsScreen(pages: [BlocDebugPage()])),
    );

void main() {
  setUp(() {
    DebugOverlayKillSwitch.reset();
    BlocStore.instance.clear();
    Bloc.observer = DebugBlocObserver();
  });

  tearDown(() {
    Bloc.observer = _NoopObserver();
    DebugOverlayKillSwitch.reset();
  });

  group('tracking', () {
    test('a cubit is tracked from creation, with its initial state', () {
      final cubit = CounterCubit();
      addTearDown(cubit.close);

      final tracked = BlocStore.instance.blocs.single;
      expect(tracked.type, 'CounterCubit');
      expect(tracked.state, 0);
      expect(tracked.changes, isEmpty, reason: 'creation is not a transition');
    });

    test('emits are recorded, newest first', () {
      final cubit = CounterCubit();
      addTearDown(cubit.close);

      cubit
        ..increment()
        ..increment();

      final tracked = BlocStore.instance.blocs.single;
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

      final blocs = BlocStore.instance.blocs;
      expect(blocs, hasLength(2));
      expect(blocs.map((x) => x.state), containsAll([1, 0]));
    });

    test('errors are captured', () {
      final cubit = CounterCubit();
      addTearDown(cubit.close);

      cubit.boom();

      final tracked = BlocStore.instance.blocs.single;
      expect(tracked.error, isA<StateError>());
      expect(tracked.stackTrace, isNotNull);
    });

    test('a closed cubit is kept, but marked', () async {
      final cubit = CounterCubit();
      cubit.increment();
      await cubit.close();

      final tracked = BlocStore.instance.blocs.single;
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

      expect(BlocStore.instance.blocs.first.isClosed, isFalse);
      expect(BlocStore.instance.blocs.last.isClosed, isTrue);
    });

    test('clearClosed drops the dead ones and keeps the live', () async {
      final closed = CounterCubit();
      await closed.close();
      final live = CounterCubit();
      addTearDown(live.close);

      BlocStore.instance.clearClosed();

      expect(BlocStore.instance.blocs.single.isClosed, isFalse);
    });
  });

  group('events — the ordering trap', () {
    // A Bloc calls onTransition and THEN emit (which fires onChange) — see
    // Bloc._on's onEmit. So the event arrives BEFORE the change it caused.
    // Assuming the reverse staples each event onto the *previous* transition.

    test('each transition carries the event that actually caused it', () async {
      final bloc = CounterBloc();
      addTearDown(bloc.close);

      bloc.add(const Increment());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const Decrement());
      await Future<void>.delayed(Duration.zero);

      final tracked = BlocStore.instance.blocs.single;
      expect(tracked.changes, hasLength(2));

      // Newest first: the Decrement (1 → 0) and the Increment (0 → 1).
      expect(tracked.changes[0].event, isA<Decrement>());
      expect(tracked.changes[0].from, 1);
      expect(tracked.changes[0].to, 0);

      expect(tracked.changes[1].event, isA<Increment>());
      expect(tracked.changes[1].from, 0);
      expect(tracked.changes[1].to, 1);
    });

    test('a bloc transition is recorded ONCE, not twice', () async {
      // onTransition and onChange both fire for the same state change. Recording
      // in both would double-log every transition.
      final bloc = CounterBloc();
      addTearDown(bloc.close);

      bloc.add(const Increment());
      await Future<void>.delayed(Duration.zero);

      expect(BlocStore.instance.blocs.single.changes, hasLength(1));
    });

    test('a plain cubit has no event', () {
      final cubit = CounterCubit();
      addTearDown(cubit.close);

      cubit.increment();

      expect(BlocStore.instance.blocs.single.changes.single.event, isNull);
    });
  });

  group('fields outside the state', () {
    // BlocObserver only ever hands over `bloc.state`. Anything else a cubit holds
    // — a sync queue, a lookup map, a counter — is invisible to it, and Flutter
    // has no reflection to go find it. So the cubit (or the app) has to point.

    test('inspect() exposes fields without touching the cubit', () {
      BlocStore.instance.inspect<CounterCubit>((c) => {'extra': c.extra});
      addTearDown(BlocStore.instance.clearInspectors);

      final cubit = CounterCubit();
      addTearDown(cubit.close);
      cubit.extra = 'hello';

      final tracked = BlocStore.instance.blocs.single;
      expect(BlocStore.instance.liveFieldsOf(tracked), {'extra': 'hello'});
    });

    test('fields are read LIVE, not snapshotted at emit time', () {
      BlocStore.instance.inspect<CounterCubit>((c) => {'extra': c.extra});
      addTearDown(BlocStore.instance.clearInspectors);

      final cubit = CounterCubit();
      addTearDown(cubit.close);

      final tracked = BlocStore.instance.blocs.single;
      expect(BlocStore.instance.liveFieldsOf(tracked)['extra'], isNull);

      // Changed with NO emit — the whole reason the detail pane has a re-read
      // button.
      cubit.extra = 'changed';

      expect(BlocStore.instance.liveFieldsOf(tracked)['extra'], 'changed');
    });

    test('DebugInspectable works too', () {
      final cubit = InspectableCubit();
      addTearDown(cubit.close);

      final tracked = BlocStore.instance.blocs.single;
      expect(BlocStore.instance.liveFieldsOf(tracked), {'from': 'the interface'});
    });

    test('a registration WINS over the interface, so you can override a cubit', () {
      BlocStore.instance.inspect<InspectableCubit>((c) => {'from': 'the registry'});
      addTearDown(BlocStore.instance.clearInspectors);

      final cubit = InspectableCubit();
      addTearDown(cubit.close);

      final tracked = BlocStore.instance.blocs.single;
      expect(BlocStore.instance.liveFieldsOf(tracked), {'from': 'the registry'});
    });

    test('a cubit exposing nothing yields no fields', () {
      final cubit = CounterCubit();
      addTearDown(cubit.close);

      expect(BlocStore.instance.liveFieldsOf(BlocStore.instance.blocs.single), isEmpty);
    });

    test('a throwing extractor does NOT take the page down', () {
      BlocStore.instance.inspect<CounterCubit>((c) => throw StateError('bad extractor'));
      addTearDown(BlocStore.instance.clearInspectors);

      final cubit = CounterCubit();
      addTearDown(cubit.close);

      final fields = BlocStore.instance.liveFieldsOf(BlocStore.instance.blocs.single);
      expect(fields.keys.single, contains('threw'));
      expect(fields.values.single.toString(), contains('bad extractor'));
    });

    test('the instance is held WEAKLY — the tool must not keep your cubits alive', () {
      final cubit = CounterCubit();
      final tracked = BlocStore.instance.blocs.single;

      // A strong reference would make this debug tool the thing leaking every
      // cubit the app ever created — the exact bug it exists to help you find.
      expect(tracked.ref, isNotNull);
      expect(tracked.ref!.target, same(cubit));

      cubit.close();
    });
  });

  group('caps', () {
    test('transitions are capped per bloc, keeping the newest', () {
      BlocStore.instance.maxChangesPerBloc = 3;
      addTearDown(() => BlocStore.instance.maxChangesPerBloc = 100);

      final cubit = CounterCubit();
      addTearDown(cubit.close);

      for (var i = 0; i < 10; i++) {
        cubit.increment();
      }

      final changes = BlocStore.instance.blocs.single.changes;
      expect(changes, hasLength(3));
      expect(changes.first.to, 10, reason: 'the newest is kept');
    });
  });

  group('the kill switch', () {
    test('nothing is tracked when it is off', () {
      DebugOverlayKillSwitch.enabled = false;

      final cubit = CounterCubit();
      addTearDown(cubit.close);
      cubit.increment();

      expect(BlocStore.instance.blocs, isEmpty);
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
      expect(BlocStore.instance.blocs.single.changes, hasLength(1));
    });
  });

  group('BlocDebugPage', () {
    testWidgets('tells you when the observer is not installed', (tester) async {
      Bloc.observer = _NoopObserver();
      BlocStore.instance.clear();

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.textContaining('Did you set Bloc.observer'), findsOneWidget);
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
      expect(BlocStore.instance.blocs.single.state, 1);
      expect(find.text('CounterCubit'), findsOneWidget);
    });

    testWidgets('tapping a cubit shows its transition history', (tester) async {
      final bloc = CounterBloc();
      addTearDown(bloc.close);

      bloc.add(const Increment());
      await Future<void>.delayed(Duration.zero);

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('CounterBloc'));
      await tester.pumpAndSettle();

      expect(find.text('Current state'), findsOneWidget);
      expect(find.text('Transitions'), findsOneWidget);
      // The event that caused it.
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
