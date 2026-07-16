// The Riverpod adapter, against a real ProviderContainer.
//
// This package is the second state-management binding, and that's the point of
// it: if StateInspector were secretly shaped around bloc, wiring a genuinely
// different API — providers, not blocs; a context object, not positional args —
// is where it would show. The core's own state_page_test proves the page needs
// no library at all; these prove one specific library reaches it.
import 'package:debug_overlay/debug_overlay.dart';
import 'package:debug_overlay_riverpod/debug_overlay_riverpod.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what it was handed, to prove chaining doesn't swallow events.
base class _SpyObserver extends ProviderObserver {
  int adds = 0;
  int updates = 0;
  int disposes = 0;
  int failures = 0;

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) => adds++;

  @override
  void didUpdateProvider(ProviderObserverContext context, Object? prev, Object? next) => updates++;

  @override
  void didDisposeProvider(ProviderObserverContext context) => disposes++;

  @override
  void providerDidFail(ProviderObserverContext context, Object error, StackTrace stackTrace) => failures++;
}

/// A modern Notifier, not the legacy StateProvider — v3 moved that to
/// `legacy.dart`, and a new package's tests shouldn't lean on a deprecated API.
class _Counter extends Notifier<int> {
  @override
  int build() => 0;

  /// A field held OUTSIDE the state — what StateInspector.inspect exists for,
  /// and the thing that silently didn't work until the adapter started passing
  /// the notifier as `instance`.
  int sets = 0;

  void set(int v) {
    state = v;
    sets++;
  }
}

final counter = NotifierProvider<_Counter, int>(_Counter.new, name: 'counter');
final unnamed = NotifierProvider<_Counter, int>(_Counter.new);
final boom = Provider<int>((ref) => throw StateError('boom'), name: 'boom');

ProviderContainer _container({ProviderObserver? next}) {
  final c = ProviderContainer(observers: [DebugRiverpodObserver(next: next)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() {
    DebugOverlayKillSwitch.reset();
    StateInspector.instance.clear();
  });

  test('reading a provider registers it, with its declared name', () {
    _container().read(counter);

    final source = StateInspector.instance.sources.single;
    expect(source.type, 'counter');
    expect(source.state, 0);
  });

  test('an unnamed provider falls back to its type, never a blank row', () {
    _container().read(unnamed);

    expect(StateInspector.instance.sources.single.type, isNotEmpty);
  });

  test('a change is recorded as a transition', () {
    final c = _container();
    c.read(counter.notifier).set(1);
    c.read(counter.notifier).set(2);

    final source = StateInspector.instance.sources.single;
    expect(source.state, 2, reason: 'the page shows the current value');
    // Newest first, like the log stream.
    expect(source.changes.first.to, 2);
    expect(source.changes.first.from, 1);
    expect(source.changes.length, 2);
  });

  test('the same provider read twice is one source, not two', () {
    // Providers are const-constructed singletons, so identity is the
    // declaration — reading it again must not fork the history.
    final c = _container();
    c.read(counter);
    c.read(counter.notifier).set(1);

    expect(StateInspector.instance.sources, hasLength(1));
  });

  group('StateInspector.inspect — fields outside the state', () {
    // Regression: the adapter recorded no `instance`, so inspect<T> had nothing
    // to read fields off and the extra fields silently never appeared. Bloc
    // worked (a bloc IS the object); Riverpod didn't, because it splits the
    // const provider declaration from the notifier that actually holds the
    // fields. The notifier is the analogue of the bloc, and the thing to pass.
    setUp(() {
      StateInspector.instance.inspect<_Counter>((c) => {'sets': c.sets});
      addTearDown(StateInspector.instance.clearInspectors);
    });

    test('a notifier field shows up on its source', () {
      final c = _container();
      c.read(counter.notifier).set(1);
      c.read(counter.notifier).set(2);

      final source = StateInspector.instance.sources.single;
      // liveFieldsOf is what the page itself calls to render the extra fields.
      expect(StateInspector.instance.liveFieldsOf(source), {'sets': 2});
    });

    test('the notifier is carried from the very first record', () {
      // Not just on later updates — the row is inspectable as soon as it exists.
      final c = _container();
      c.read(counter);

      expect(StateInspector.instance.sources.single.ref?.target, isA<_Counter>());
    });

    test('a plain Provider has no notifier, and that is not an error', () {
      // Its value already IS the state; there is nothing else to read.
      final plain = Provider<int>((ref) => 7, name: 'plain');
      _container().read(plain);

      final source = StateInspector.instance.sources.single;
      expect(source.state, 7);
      expect(source.ref?.target, isNull);
    });
  });

  test('two different providers are two sources', () {
    final c = _container();
    c.read(counter);
    c.read(unnamed);

    expect(StateInspector.instance.sources, hasLength(2));
  });

  test('a provider that throws is recorded as an error', () {
    final c = _container();
    // Riverpod caches the failure and rethrows on read — either way, the
    // observer has already seen it by the time we get here.
    try {
      c.read(boom);
    } catch (_) {}

    final source = StateInspector.instance.sources.single;
    expect(source.error, isA<StateError>());
  });

  test('disposing the container closes its sources', () {
    final c = ProviderContainer(observers: [const DebugRiverpodObserver()]);
    c.read(counter);
    expect(StateInspector.instance.sources.single.isClosed, isFalse);

    c.dispose();

    expect(StateInspector.instance.sources.single.isClosed, isTrue);
  });

  test('chaining forwards every event — your own observer keeps working', () {
    final spy = _SpyObserver();
    final c = _container(next: spy);

    c.read(counter);
    c.read(counter.notifier).set(1);
    try {
      c.read(boom);
    } catch (_) {}

    expect(spy.adds, greaterThan(0));
    expect(spy.updates, 1);
    expect(spy.failures, 1);
  });

  test('the kill switch stops recording — a release build buffers nothing', () {
    DebugOverlayKillSwitch.enabled = false;
    addTearDown(DebugOverlayKillSwitch.reset);

    final c = _container();
    c.read(counter);
    c.read(counter.notifier).set(1);

    expect(StateInspector.instance.sources, isEmpty);
  });
}
