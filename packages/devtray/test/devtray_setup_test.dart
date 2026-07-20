import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sink that records nothing but its own existence.
class _NullSink extends LogSink {
  @override
  String get name => 'null';

  @override
  Future<void> write(List<LogEntry> batch) async {}
}

/// Runs [body], then restores the `debugPrint` global that `runDebugApp` hooks.
///
/// flutter_test asserts that a test leaves foundation globals untouched, and it
/// checks *before* tearDown runs — so the restore has to happen inside the test
/// body. Same helper as run_debug_app_test.dart, for the same reason.
Future<void> withDebugPrintRestored(Future<void> Function() body) async {
  final original = debugPrint;
  try {
    await body();
  } finally {
    stopCapturingDebugPrint();
    debugPrint = original;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DevtrayLog.instance
      ..clear()
      ..clearContext()
      ..clearEnrichers();
    DevtrayNet.instance
      ..clear()
      ..excludedUrlPatterns.clear()
      ..maxEntries = 500;
    DevtrayState.instance
      ..clear()
      ..clearInspectors();
    DevtrayJank.instance
      ..stop()
      ..clear();
  });

  tearDown(() {
    Devtray.enabled = true;
    DevtrayJank.instance.stop();
  });

  group('configure', () {
    testWidgets('applies every subsystem from one callback', (tester) async => withDebugPrintRestored(() async {
      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d
          ..excludeUrls(['/health', '/metrics'])
          ..network(maxEntries: 42)
          ..logs(maxEntries: 77)
          ..context({'build': '1.4.2'})
          ..enrich('nav', () => {'screen': 'home'})
          ..logTo(_NullSink())
          ..state(maxChangesPerSource: 9),
      );
      await tester.pumpAndSettle();

      expect(DevtrayNet.instance.excludedUrlPatterns, containsAll(['/health', '/metrics']));
      expect(DevtrayNet.instance.maxEntries, 42);
      expect(DevtrayLog.instance.maxEntries, 77);
      expect(DevtrayLog.instance.context['build'], '1.4.2');
      expect(DevtrayExport.instance.sinks, hasLength(1));
      expect(DevtrayState.instance.maxChangesPerSource, 9);

      await DevtrayExport.instance.dispose();
    }));

    testWidgets('settings it applies survive capture being switched on later', (tester) async => withDebugPrintRestored(() async {
      // runDebugApp no longer forces the switch on, so `configure` observes
      // whatever the app set. What has to hold is that its *settings* land
      // regardless: a support build that boots with capture off and enables it
      // mid-session must find its excluded URLs already registered, not missing
      // because of when the app happened to start.
      Devtray.enabled = false;
      addTearDown(Devtray.reset);

      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d..excludeUrls(['/health']),
      );
      await tester.pumpAndSettle();

      Devtray.enabled = true;
      expect(DevtrayNet.instance.excludedUrlPatterns, contains('/health'));
    }));

    testWidgets('runs AFTER the capture hooks, so it can log', (tester) async => withDebugPrintRestored(() async {
      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d.raw(() => DevtrayLog.instance.log('from configure', tag: 'setup')),
      );
      await tester.pumpAndSettle();

      expect(
        DevtrayLog.instance.entries.any((e) => e.message == 'from configure'),
        isTrue,
        reason: 'a line written during configure must be captured, not dropped',
      );
    }));

    testWidgets('runs BEFORE setup, so bootstrap traffic is already configured', (tester) async => withDebugPrintRestored(() async {
      final order = <String>[];

      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d.raw(() => order.add('configure')),
        setup: () async => order.add('setup'),
      );
      await tester.pumpAndSettle();

      // An app bootstrap may reasonably log or make requests; the overlay
      // should already be set up to record them.
      expect(order, ['configure', 'setup']);
    }));

    testWidgets('still runs when capture is off', (tester) async => withDebugPrintRestored(() async {
      var ran = false;
      Devtray.enabled = false;
      addTearDown(Devtray.reset);

      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d.raw(() => ran = true),
      );
      await tester.pumpAndSettle();

      // `configure` sets *settings*, and Devtray.enabled is flippable at
      // runtime — a support build that switches capture on mid-session must
      // find its excluded URLs and enrichers already registered, not missing
      // because the app happened to boot with capture off.
      expect(ran, isTrue);
    }));

    testWidgets('app is built AFTER setup, so it can read what the bootstrap made', (tester) async => withDebugPrintRestored(() async {
      final order = <String>[];

      runDebugApp(
        () {
          order.add('app');
          return const SizedBox.shrink();
        },
        setup: () async => order.add('setup'),
      );
      await tester.pumpAndSettle();

      // The whole reason `app` is a builder. As a plain widget it was
      // constructed at the call site — before this function was even entered —
      // so an app reading dotenv or a Firebase handle threw before setup ran.
      expect(order, ['setup', 'app']);
    }));

    testWidgets('is optional', (tester) async => withDebugPrintRestored(() async {
      runDebugApp(() => const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(DevtrayNet.instance.excludedUrlPatterns, isEmpty);
    }));
  });

  group('coverage', () {
    testWidgets('every tunable on every store is reachable', (tester) async => withDebugPrintRestored(() async {
      // The point of the facade is that it is the ONE place to look. A store
      // field it cannot set sends you back to the singletons, and the split
      // setup returns — so this asserts the whole surface, and fails when a new
      // knob is added without a way to reach it from here.
      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d
          ..excludeUrls(['/x'])
          ..network(maxEntries: 11, maxBodyChars: 2048, errorReporting: NetworkErrorReporting.serverAndTransport)
          ..logs(maxEntries: 12, flushOnPause: false)
          ..state(maxChangesPerSource: 13, maxClosedSources: 14, retainStateObjects: true)
          ..detectFreezes(
            threshold: const Duration(milliseconds: 300),
            slowFrameThreshold: const Duration(milliseconds: 40),
            heartbeatInterval: const Duration(milliseconds: 80),
            maxFreezes: 15,
            maxSlowFrames: 16,
          )
          ..launcher(false)
          ..openOnStart(),
      );
      await tester.pumpAndSettle();

      final network = DevtrayNet.instance;
      expect(network.excludedUrlPatterns, contains('/x'));
      expect(network.maxEntries, 11);
      expect(network.maxBodyChars, 2048);
      expect(network.errorReporting.value, NetworkErrorReporting.serverAndTransport);

      expect(DevtrayLog.instance.maxEntries, 12);
      expect(DevtrayExport.instance.flushOnPause, isFalse);

      final state = DevtrayState.instance;
      expect(state.maxChangesPerSource, 13);
      expect(state.maxClosedSources, 14);
      expect(state.retainStateObjects, isTrue);

      expect(Devtray.showLauncher, isFalse);
      expect(Devtray.isOpen, isTrue);

      final watchdog = DevtrayJank.instance;
      expect(watchdog.freezeThreshold, const Duration(milliseconds: 300));
      expect(watchdog.slowFrameThreshold, const Duration(milliseconds: 40));
      expect(watchdog.heartbeatInterval, const Duration(milliseconds: 80));
      expect(watchdog.maxFreezes, 15);
      expect(watchdog.maxSlowFrames, 16);

      // Restore the ones with process-wide effect, and stop the real timer
      // before flutter_test checks for pending ones.
      watchdog.stop();
      DevtrayExport.instance.flushOnPause = true;
      state.retainStateObjects = false;
      Devtray.reset();
    }));

    testWidgets('raw() covers anything the facade does not', (tester) async => withDebugPrintRestored(() async {
      // The escape hatch matters as much as the coverage: a missing convenience
      // method must never be a reason to configure something OUTSIDE the
      // callback, which is where the ordering guarantee is lost.
      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d.raw(() => DevtrayMocks.instance.rulesEnabled.value = false),
      );
      await tester.pumpAndSettle();

      expect(DevtrayMocks.instance.rulesEnabled.value, isFalse);
      DevtrayMocks.instance.rulesEnabled.value = true;
    }));
  });

  group('the methods reach the real singletons', () {
    testWidgets('inspect registers against DevtrayState', (tester) async => withDebugPrintRestored(() async {
      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d.inspect<_Probe>((p) => {'value': p.value}),
      );
      await tester.pumpAndSettle();

      // Read back through the inspector, which is the only observable: the
      // facade must not keep its own registry that the page never sees.
      expect(DevtrayState.instance.fieldsFor(_Probe(7)), {'value': 7});
    }));

    testWidgets('inspectAll registers several typed extractors at once', (tester) async => withDebugPrintRestored(() async {
      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (devtray) => devtray.inspectAll([
          // The variance question this exists to answer: an Inspect<_Probe> has
          // to be usable in a List<Inspect<Object>>, and the callback must
          // still receive a _Probe rather than an Object needing a cast.
          Inspect<_Probe>((p) => {'value': p.value}),
          Inspect<_OtherProbe>((p) => {'name': p.name}),
        ]),
      );
      await tester.pumpAndSettle();

      expect(DevtrayState.instance.fieldsFor(_Probe(7)), {'value': 7});
      expect(DevtrayState.instance.fieldsFor(_OtherProbe('x')), {'name': 'x'});
    }));

    testWidgets('inspectAll and inspect<T> reach the same registry', (tester) async => withDebugPrintRestored(() async {
      // Both spellings must be interchangeable — inspectAll is a convenience,
      // not a second mechanism with its own store.
      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (devtray) => devtray
          ..inspect<_Probe>((p) => {'via': 'inspect'})
          ..inspectAll([Inspect<_OtherProbe>((p) => {'via': 'inspectAll'})]),
      );
      await tester.pumpAndSettle();

      expect(DevtrayState.instance.fieldsFor(_Probe(1)), {'via': 'inspect'});
      expect(DevtrayState.instance.fieldsFor(_OtherProbe('y')), {'via': 'inspectAll'});
    }));

    testWidgets('detectFreezes starts the watchdog with the given thresholds', (tester) async => withDebugPrintRestored(() async {
      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d.detectFreezes(threshold: const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();

      expect(DevtrayJank.instance.isRunning, isTrue);
      expect(DevtrayJank.instance.freezeThreshold, const Duration(milliseconds: 400));

      // Inside the body, not tearDown: the heartbeat is a real periodic timer,
      // and flutter_test asserts no timers are pending *before* tearDown runs.
      // Its still being alive here is the assertion above passing, not a leak.
      DevtrayJank.instance.stop();
    }));

    testWidgets('logToAsync opens the sink before the app runs', (tester) async => withDebugPrintRestored(() async {
      var opened = false;

      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d.logToAsync(() async {
          // A real file sink creates a directory and prunes old sessions, so
          // this is genuinely async — which is why `configure` cannot simply
          // take the sink itself.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          opened = true;
          return _NullSink();
        }),
        setup: () async {
          // The guarantee: a bootstrap that logs must reach a sink that is
          // already open, not fall in the gap between "configured" and "ready".
          expect(opened, isTrue, reason: 'the sink must be open before setup runs');
        },
      );
      await tester.pumpAndSettle();

      expect(DevtrayExport.instance.sinks, hasLength(1));
      await DevtrayExport.instance.dispose();
    }));

    testWidgets('a sink that fails to open is reported, not fatal', (tester) async => withDebugPrintRestored(() async {
      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d.logToAsync(() async => throw StateError('no such directory')),
      );
      await tester.pumpAndSettle();

      // A debug tool must not take down the launch of the app it exists to
      // observe — but it must not fail silently either.
      expect(DevtrayExport.instance.sinks, isEmpty);
      expect(
        DevtrayLog.instance.entries.any((e) => e.tag == 'devtray' && e.message.contains('no such directory')),
        isTrue,
      );
    }));

    testWidgets('enrich adds fields to entries logged afterwards', (tester) async => withDebugPrintRestored(() async {
      runDebugApp(
        () => const SizedBox.shrink(),
        configure: (d) => d.enrich('probe', () => {'live': true}),
      );
      await tester.pumpAndSettle();

      DevtrayLog.instance.log('after configure');
      expect(DevtrayLog.instance.entries.first.fields['live'], true);
    }));
  });
}

class _Probe {
  final int value;
  _Probe(this.value);
}

class _OtherProbe {
  final String name;
  _OtherProbe(this.name);
}
