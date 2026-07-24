import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registration is process-global — every store is a singleton — so a listener
/// left behind by one test would fire for every test after it.
void _resetAll() {
  // `reset` drops every listener on every store; the rest is buffered data.
  Devtray.reset();
  Devtray.enabled = true;
  DevtrayLog.instance
    ..clearEnrichers()
    ..clear();
  DevtrayNet.instance
    ..clear()
    ..excludedUrlPatterns.clear();
  // A ValueNotifier, so it survives `clear()` — and a test that narrows it
  // would otherwise silence every error-forwarding test after it.
  DevtrayNet.instance.errorReporting.value = NetworkErrorReporting.all;
  DevtrayNav.instance.clear();
  DevtrayState.instance.clear();
  DevtrayJank.instance.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_resetAll);
  tearDown(() {
    _resetAll();
    DevtrayJank.instance.stop();
  });

  group('logs', () {
    test('onLog sees every entry, onError only the errors', () {
      final logged = <String>[];
      final errors = <String>[];
      DevtrayLog.instance.onLog((e) => logged.add(e.message));
      DevtrayLog.instance.onError((e) => errors.add(e.message));

      Devtray.log('ordinary');
      Devtray.report('boom');

      expect(logged, ['ordinary', 'boom']);
      expect(errors, ['boom'], reason: 'onError must not see debug lines');
    });

    test('the disposer stops delivery', () {
      final seen = <String>[];
      final off = DevtrayLog.instance.onLog((e) => seen.add(e.message));

      Devtray.log('before');
      off();
      Devtray.log('after');

      expect(seen, ['before']);
    });

    test('calling the disposer twice removes only its own registration', () {
      var calls = 0;
      void listener(LogEntry _) => calls++;

      final off = DevtrayLog.instance.onLog(listener);
      DevtrayLog.instance.onLog(listener); // the same closure, registered twice

      off();
      off(); // must not take the second registration with it

      Devtray.log('x');
      expect(calls, 1);
    });

    test('the entry is fully recorded before listeners run', () {
      LogEntry? seen;
      var countAtCallback = -1;
      DevtrayLog.instance.onLog((e) {
        seen = e;
        countAtCallback = DevtrayLog.instance.entries.length;
      });

      Devtray.log('hello', tag: 'auth', fields: {'userId': 7});

      expect(seen?.message, 'hello');
      expect(seen?.tag, 'auth');
      expect(seen?.fields['userId'], 7);
      expect(countAtCallback, 1, reason: 'observe-only: the entry is already stored');
    });

    test('nothing fires while capture is off', () {
      var calls = 0;
      DevtrayLog.instance.onLog((_) => calls++);

      Devtray.enabled = false;
      Devtray.log('dropped');
      expect(calls, 0);

      Devtray.enabled = true;
      Devtray.log('kept');
      expect(calls, 1);
    });
  });

  group('a listener that throws', () {
    test('does not stop the entry being recorded', () {
      DevtrayLog.instance.onLog((_) => throw StateError('bad listener'));

      Devtray.log('still recorded');

      expect(
        DevtrayLog.instance.entries.map((e) => e.message),
        contains('still recorded'),
      );
    });

    test('does not stop the other listeners', () {
      final reached = <String>[];
      DevtrayNet.instance.onResponse((_) => reached.add('first'));
      DevtrayNet.instance.onResponse((_) => throw StateError('bad'));
      DevtrayNet.instance.onResponse((_) => reached.add('third'));

      final entry = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/x'))!;
      DevtrayNet.instance.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);

      expect(reached, ['first', 'third']);
    });

    test('is reported as an error line naming the list', () {
      DevtrayNet.instance.onResponse((_) => throw StateError('bad'));

      final entry = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/x'))!;
      DevtrayNet.instance.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);

      final reported = DevtrayLog.instance.entries.where((e) => e.tag == 'devtray');
      expect(reported, isNotEmpty);
      expect(reported.first.message, contains('network response'));
      expect(reported.first.level, LogLevel.error);
    });

    test('a throwing log listener does not recurse forever', () {
      // The failure is itself logged, which runs the log listeners again.
      DevtrayLog.instance.onLog((_) => throw StateError('always'));

      expect(() => Devtray.log('trigger'), returnsNormally);
    });
  });

  test('a listener may unsubscribe from inside its own callback', () {
    final seen = <String>[];
    late final DevtrayUnsubscribe off;
    off = DevtrayLog.instance.onLog((e) {
      seen.add(e.message);
      off(); // mutates the list mid-notification
    });

    Devtray.log('one');
    Devtray.log('two');

    expect(seen, ['one'], reason: 'it removed itself after the first');
  });

  group('network', () {
    test('onRequest fires at departure, onResponse at completion', () {
      final events = <String>[];
      DevtrayNet.instance.onRequest((r) => events.add('start ${r.method}'));
      DevtrayNet.instance.onResponse((r) => events.add('done ${r.statusCode}'));

      final entry = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/x'))!;
      expect(events, ['start GET'], reason: 'no outcome yet');

      DevtrayNet.instance.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);
      expect(events, ['start GET', 'done 200']);
    });

    test('onFailure fires only for failures, and regardless of errorReporting', () {
      DevtrayNet.instance.errorReporting.value = NetworkErrorReporting.none;

      final failures = <int?>[];
      DevtrayNet.instance.onFailure((r) => failures.add(r.statusCode));

      final ok = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/ok'))!;
      DevtrayNet.instance.complete(ok.id, status: NetworkLogStatus.success, statusCode: 200);

      final bad = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/bad'))!;
      DevtrayNet.instance.complete(bad.id, status: NetworkLogStatus.failed, statusCode: 500);

      expect(failures, [500], reason: 'suppressing the log line must not suppress the callback');
    });

    test('an excluded URL notifies nothing', () {
      DevtrayNet.instance.excludedUrlPatterns.add('/health');
      var calls = 0;
      DevtrayNet.instance.onRequest((_) => calls++);

      expect(DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/health')), isNull);
      expect(calls, 0);
    });

    test('a failed request reaches the log store error listener too', () {
      final errors = <ErrorSource?>[];
      DevtrayLog.instance.onError((e) => errors.add(e.source));

      final entry = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/x'))!;
      DevtrayNet.instance.complete(entry.id, status: NetworkLogStatus.failed, statusCode: 500);

      expect(errors, [ErrorSource.network]);
    });
  });

  group('nav', () {
    test('onScreen fires on entry, onScreenLeave with a finished visit', () {
      final entered = <String>[];
      final left = <String>[];
      DevtrayNav.instance.onScreen((v) => entered.add(v.name));
      DevtrayNav.instance.onScreenLeave((v) {
        left.add(v.name);
        expect(v.leftAt, isNotNull, reason: 'the span is closed before the callback');
        expect(v.duration, isNotNull);
      });

      DevtrayNav.instance.enter('home');
      DevtrayNav.instance.enter('checkout');
      DevtrayNav.instance.leave('checkout');

      expect(left, ['checkout']);
      // Returning to `home` is its own visit, so it is reported as an arrival.
      expect(entered, ['home', 'checkout', 'home']);
    });

    test('the current screen is published before listeners run', () {
      String? screenDuringCallback;
      DevtrayNav.instance.onScreen((_) {
        screenDuringCallback = DevtrayContext.instance.values[DevtrayNav.screenField] as String?;
      });

      DevtrayNav.instance.enter('checkout');

      expect(screenDuringCallback, 'checkout');
    });

    test('a pop that matches nothing notifies nothing', () {
      var calls = 0;
      DevtrayNav.instance.onScreenLeave((_) => calls++);

      DevtrayNav.instance.leave('never-pushed');

      expect(calls, 0);
    });
  });

  group('state', () {
    test('onStateChange carries the source and the change together', () {
      final seen = <StateChange>[];
      DevtrayState.instance.onStateChange(seen.add);

      DevtrayState.instance.record(1, type: 'CartCubit', from: 0, to: 1);

      expect(seen, hasLength(1));
      expect(seen.single.type, 'CartCubit');
      expect(seen.single.change.from, 0);
      expect(seen.single.change.to, 1);
      expect(seen.single.source.state, 1, reason: 'the source holds the new value already');
    });

    test('onStateError fires with the error attached', () {
      final seen = <TrackedSource>[];
      DevtrayState.instance.onStateError(seen.add);

      DevtrayState.instance.record(1, type: 'CartCubit', from: 0, to: 1);
      DevtrayState.instance.recordError(1, StateError('nope'), StackTrace.current);

      expect(seen, hasLength(1));
      expect(seen.single.error, isA<StateError>());
      expect(seen.single.stackTrace, isNotNull);
    });

    test('an error on an unknown source notifies nothing', () {
      var calls = 0;
      DevtrayState.instance.onStateError((_) => calls++);

      DevtrayState.instance.recordError(999, StateError('nope'), StackTrace.current);

      expect(calls, 0);
    });
  });

  group('clearListeners', () {
    /// Registers one listener on every store, each appending its own name.
    List<String> registerAll() {
      final hits = <String>[];
      DevtrayLog.instance.onLog((_) => hits.add('log'));
      DevtrayNet.instance.onRequest((_) => hits.add('request'));
      DevtrayNav.instance.onScreen((_) => hits.add('screen'));
      DevtrayState.instance.onStateChange((_) => hits.add('state'));
      DevtrayJank.instance.onFreeze((_) => hits.add('freeze'));
      return hits;
    }

    /// Provokes one capture on each store, so every listener above would fire.
    void captureOnEvery() {
      Devtray.log('x');
      DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/x'));
      DevtrayNav.instance.enter('home');
      DevtrayState.instance.record(1, type: 'C', from: 0, to: 1);
      DevtrayJank.instance.recordFreezeForTesting(
        FreezeEvent(start: DateTime(2026), end: DateTime(2026), duration: Duration.zero),
      );
    }

    /// Each per-store clear drops its own subject and leaves the others alone.
    final cases = <String, (void Function(), String)>{
      'clearLogListeners': (Devtray.clearLogListeners, 'log'),
      'clearNetworkListeners': (Devtray.clearNetworkListeners, 'request'),
      'clearNavListeners': (Devtray.clearNavListeners, 'screen'),
      'clearStateListeners': (Devtray.clearStateListeners, 'state'),
      'clearJankListeners': (Devtray.clearJankListeners, 'freeze'),
    };

    for (final entry in cases.entries) {
      final (clear, dropped) = entry.value;
      test('${entry.key} drops only $dropped', () {
        final hits = registerAll();

        clear();
        captureOnEvery();

        expect(hits, isNot(contains(dropped)));
        expect(
          hits.toSet(),
          cases.values.map((c) => c.$2).toSet().difference({dropped}),
          reason: 'every other store keeps its listener',
        );
      });
    }

    test('Devtray.clearListeners drops every store at once', () {
      final hits = registerAll();

      Devtray.clearListeners();
      captureOnEvery();

      expect(hits, isEmpty);
    });

    test('a disposer for an already-cleared listener is harmless', () {
      final off = DevtrayLog.instance.onLog((_) {});
      Devtray.clearListeners();

      expect(() => off(), returnsNormally);
    });

    test('capture still works after clearing — only the callbacks went', () {
      DevtrayLog.instance.onLog((_) {});
      Devtray.clearListeners();

      Devtray.log('still recorded');

      expect(DevtrayLog.instance.entries.map((e) => e.message), contains('still recorded'));
    });
  });

  group('jank', () {
    test('onFreeze fires with the detected event', () {
      final seen = <Duration>[];
      DevtrayJank.instance.onFreeze((f) => seen.add(f.duration));

      DevtrayJank.instance.recordFreezeForTesting(
        FreezeEvent(
          start: DateTime(2026, 7, 24, 12),
          end: DateTime(2026, 7, 24, 12, 0, 1),
          duration: const Duration(seconds: 1),
        ),
      );

      expect(seen, [const Duration(seconds: 1)]);
    });
  });

  testWidgets('the facade registers listeners on every store', (tester) async {
    final original = debugPrint;
    final hits = <String>[];

    runDebugApp(
      () => const SizedBox.shrink(),
      configure: (d) => d
        ..onLog((_) => hits.add('log'))
        ..onError((_) => hits.add('error'))
        ..onRequest((_) => hits.add('request'))
        ..onResponse((_) => hits.add('response'))
        ..onFailure((_) => hits.add('failure'))
        ..onScreen((_) => hits.add('screen'))
        ..onScreenLeave((_) => hits.add('leave'))
        ..onStateChange((_) => hits.add('state'))
        ..onStateError((_) => hits.add('stateError'))
        ..onFreeze((_) => hits.add('freeze'))
        ..onSlowFrame((_) => hits.add('slowFrame')),
    );
    await tester.pumpAndSettle();

    Devtray.log('x');
    final entry = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/x'))!;
    DevtrayNet.instance.complete(entry.id, status: NetworkLogStatus.failed, statusCode: 500);
    DevtrayNav.instance.enter('home');
    DevtrayNav.instance.enter('next');
    DevtrayNav.instance.leave('next');
    DevtrayState.instance.record(1, type: 'C', from: 0, to: 1);
    DevtrayState.instance.recordError(1, StateError('e'), StackTrace.current);
    DevtrayJank.instance.recordFreezeForTesting(
      FreezeEvent(start: DateTime(2026), end: DateTime(2026), duration: Duration.zero),
    );

    expect(
      hits.toSet(),
      containsAll(<String>{
        'log',
        'error',
        'request',
        'response',
        'failure',
        'screen',
        'leave',
        'state',
        'stateError',
        'freeze',
      }),
    );

    // `runDebugApp` hooks debugPrint, and flutter_test asserts a test leaves
    // foundation globals untouched — checked before tearDown, so it restores
    // here. Same reason as devtray_setup_test.dart.
    stopCapturingDebugPrint();
    debugPrint = original;
  });
}
