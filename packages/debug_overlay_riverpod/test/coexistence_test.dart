// bloc and Riverpod, feeding the same page at once.
//
// This is the payoff of keeping StateDebugPage in the core: it reads from
// StateInspector and nothing else, so the bindings are additive. An app
// migrating from bloc to Riverpod — which is when a state inspector is most
// useful — sees both halves in one list, and neither adapter knows the other
// exists.
//
// It lives here because nowhere else can host it: the core has no state
// library, and debug_overlay_bloc has no riverpod. Both are DEV dependencies of
// this package only; nothing in lib/ touches bloc.
import 'package:bloc/bloc.dart';
import 'package:debug_overlay/debug_overlay.dart';
import 'package:debug_overlay_bloc/debug_overlay_bloc.dart';
import 'package:debug_overlay_riverpod/debug_overlay_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CartCubit extends Cubit<int> {
  _CartCubit() : super(0);
  void add() => emit(state + 1);
}

class _Session extends Notifier<String> {
  @override
  String build() => 'anonymous';

  void signIn(String user) => state = user;
}

final sessionProvider = NotifierProvider<_Session, String>(_Session.new, name: 'sessionProvider');

base class _NoopObserver extends ProviderObserver {
  const _NoopObserver();
}

/// Bloc.observer is global, so it has to be put back — and BlocObserver is
/// abstract, so "back" needs a concrete no-op.
class _NoopBlocObserver extends BlocObserver {}

Widget _host() => const MaterialApp(
      home: Scaffold(body: DebugToolsScreen(pages: [StateDebugPage()])),
    );

void main() {
  setUp(() {
    DebugOverlayKillSwitch.reset();
    StateInspector.instance.clear();
    Bloc.observer = DebugBlocObserver();
  });

  tearDown(() => Bloc.observer = _NoopBlocObserver());

  testWidgets('both libraries show up on the one page', (tester) async {
    final cart = _CartCubit()..add();
    addTearDown(cart.close);

    final container = ProviderContainer(observers: [const DebugRiverpodObserver()]);
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).signIn('ada');

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('_CartCubit'), findsOneWidget);
    expect(find.text('sessionProvider'), findsOneWidget);
  });

  test('each keeps its own history — the two do not bleed into each other', () {
    final cart = _CartCubit()
      ..add()
      ..add();
    addTearDown(cart.close);

    final container = ProviderContainer(observers: [const DebugRiverpodObserver()]);
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).signIn('ada');

    final sources = StateInspector.instance.sources;
    expect(sources, hasLength(2));

    final cubit = sources.firstWhere((s) => s.type == '_CartCubit');
    final provider = sources.firstWhere((s) => s.type == 'sessionProvider');

    expect(cubit.state, 2);
    expect(cubit.changes, hasLength(2));

    expect(provider.state, 'ada');
    expect(provider.changes, hasLength(1));
  });

  test('the kill switch stops both at once', () {
    // One switch, whatever is feeding it — a release build must buffer nothing
    // from either library.
    DebugOverlayKillSwitch.enabled = false;
    addTearDown(DebugOverlayKillSwitch.reset);

    final cart = _CartCubit()..add();
    addTearDown(cart.close);

    final container = ProviderContainer(observers: [const _NoopObserver(), const DebugRiverpodObserver()]);
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).signIn('ada');

    expect(StateInspector.instance.sources, isEmpty);
  });
}
