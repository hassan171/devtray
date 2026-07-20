import 'package:devtray/devtray.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The watchdog registers a timings callback, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  final watchdog = DevtrayJank.instance;

  setUp(() {
    watchdog
      ..stop()
      ..clear()
      ..heartbeatInterval = const Duration(milliseconds: 100)
      ..freezeThreshold = const Duration(milliseconds: 250);
  });

  tearDown(watchdog.stop);

  group('the heartbeat', () {
    test('records nothing while the isolate keeps up', () {
      fakeAsync((async) {
        watchdog.start();
        // Time advancing smoothly is an isolate that never blocked.
        async.elapse(const Duration(seconds: 5));
        expect(watchdog.freezes, isEmpty);
      });
    });

    // NOT TESTED HERE: that a real freeze is detected.
    //
    // Detection compares wall-clock (`DateTime.now()`) against the interval a
    // timer asked for. fakeAsync controls the timer clock but not the wall
    // clock, so an elapsed fake second produces no wall-clock gap and no
    // freeze — and genuinely blocking the isolate in a test would block the
    // test runner with it.
    //
    // So the detector's arithmetic is covered by [_overshootOf] below, and
    // everything downstream of it — buffering, capping, rendering — is driven
    // through `recordFreezeForTesting`. What remains unverified by any test is
    // the wiring between the timer and that arithmetic; it is four lines, and
    // this note is here so nobody mistakes green tests for proof it fires.

    test('the threshold is above ordinary timer jitter', () {
      // Timers routinely run a few ms late. A threshold near zero would report
      // constant phantom freezes, which would make the lane useless noise.
      expect(watchdog.freezeThreshold.inMilliseconds, greaterThan(100));
    });

    group('the overshoot arithmetic', () {
      final at = DateTime(2026, 7, 19, 14, 30);
      const interval = Duration(milliseconds: 100);
      const threshold = Duration(milliseconds: 250);

      FreezeEvent? between(Duration elapsed) => DevtrayJank.freezeBetween(
        last: at,
        now: at.add(elapsed),
        interval: interval,
        threshold: threshold,
      );

      test('a punctual tick is not a freeze', () {
        expect(between(interval), isNull);
      });

      test('ordinary jitter is not a freeze', () {
        // 40ms late — the kind of lateness every timer shows.
        expect(between(const Duration(milliseconds: 140)), isNull);
      });

      test('just under the threshold is not a freeze', () {
        expect(between(const Duration(milliseconds: 349)), isNull);
      });

      test('past the threshold is a freeze, measured as the overshoot', () {
        // 1100ms elapsed for a 100ms interval: the isolate owed 1000ms.
        final freeze = between(const Duration(milliseconds: 1100));

        expect(freeze, isNotNull);
        expect(
          freeze!.duration,
          const Duration(milliseconds: 1000),
          reason: 'the freeze is the time beyond what the timer asked for, not the whole gap',
        );
      });

      test('the span starts when the tick was DUE, not when it last ran', () {
        final freeze = between(const Duration(milliseconds: 1100))!;

        // The isolate was fine for the first 100ms — it was doing the waiting
        // it was told to. Drawing the bar from `last` would overstate every
        // freeze by one interval.
        expect(freeze.start, at.add(interval));
        expect(freeze.end, at.add(const Duration(milliseconds: 1100)));
      });
    });

    test('start is idempotent, and stop actually stops', () {
      fakeAsync((async) {
        watchdog.start();
        expect(watchdog.isRunning, isTrue);

        watchdog.start(); // no second timer
        expect(watchdog.isRunning, isTrue);

        watchdog.stop();
        expect(watchdog.isRunning, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(watchdog.freezes, isEmpty);
      });
    });

    test('does nothing while the kill switch is off', () {
      Devtray.enabled = false;
      addTearDown(() => Devtray.enabled = true);

      watchdog.start();

      // A release build that calls start() must still pay nothing.
      expect(watchdog.isRunning, isFalse);
    });
  });

  group('the freeze buffer', () {
    test('is capped, oldest dropped first', () {
      watchdog
        ..maxFreezes = 3
        ..clear();

      // Push directly — the point here is the ring buffer, not the detector.
      for (var i = 0; i < 5; i++) {
        final start = DateTime(2026, 1, 1).add(Duration(seconds: i));
        watchdog.recordFreezeForTesting(
          FreezeEvent(start: start, end: start.add(const Duration(milliseconds: 400)), duration: const Duration(milliseconds: 400)),
        );
      }

      expect(watchdog.freezes, hasLength(3));
      // Newest last: the first two fell off the front.
      expect(watchdog.freezes.first.start.second, 2);
      expect(watchdog.freezes.last.start.second, 4);
    });

    test('clear empties both buffers', () {
      watchdog.recordFreezeForTesting(
        FreezeEvent(start: DateTime(2026), end: DateTime(2026), duration: const Duration(milliseconds: 300)),
      );
      expect(watchdog.freezes, isNotEmpty);

      watchdog.clear();
      expect(watchdog.freezes, isEmpty);
      expect(watchdog.slowFrames, isEmpty);
    });
  });

  group('on the timeline', () {
    setUp(() {
      DevtrayLog.instance.clear();
      DevtrayNet.instance.clear();
      DevtrayState.instance.clear();
    });

    test('a freeze becomes an error-marked span in the jank lane', () {
      final start = DateTime.now().subtract(const Duration(seconds: 2));
      watchdog.recordFreezeForTesting(
        FreezeEvent(start: start, end: start.add(const Duration(milliseconds: 900)), duration: const Duration(milliseconds: 900)),
      );

      final events = collectTimelineEvents(
        from: DateTime.now().subtract(const Duration(seconds: 10)),
        to: DateTime.now(),
      );

      final jank = events.where((e) => e.lane == TimelineLane.jank).toList();
      expect(jank, hasLength(1));
      expect(jank.single.isError, isTrue, reason: 'a freeze past the threshold is never fine');
      expect(jank.single.hasDuration, isTrue, reason: 'it draws as a span, not a mark');
      expect(jank.single.label, contains('900ms'));
    });

    test('the jank lane can be muted like any other', () {
      final start = DateTime.now().subtract(const Duration(seconds: 1));
      watchdog.recordFreezeForTesting(
        FreezeEvent(start: start, end: start.add(const Duration(milliseconds: 400)), duration: const Duration(milliseconds: 400)),
      );

      final events = collectTimelineEvents(
        from: DateTime.now().subtract(const Duration(seconds: 10)),
        to: DateTime.now(),
        includeJank: false,
      );

      expect(events.where((e) => e.lane == TimelineLane.jank), isEmpty);
    });

    testWidgets('tapping a freeze opens a dialog showing what else was happening', (tester) async {
      // A request that was in flight when everything stopped — the shape of the
      // thing you actually go looking for.
      final req = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/huge'));
      DevtrayNet.instance.complete(req!.id, status: NetworkLogStatus.success, statusCode: 200);

      final start = DateTime.now();
      watchdog.recordFreezeForTesting(
        FreezeEvent(start: start, end: start.add(const Duration(milliseconds: 900)), duration: const Duration(milliseconds: 900)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DevtrayThemeScope(
            theme: const DevtrayTheme(),
            child: Scaffold(
              body: SizedBox(height: 400, child: Builder(builder: const TimelineDebugPage().build)),
            ),
          ),
        ),
      );
      await tester.pump();

      final box = tester.getRect(find.byType(CustomPaint).last);
      await tester.tapAt(Offset(box.right - 6, box.top + TimelineMetrics.laneCenter(TimelineLane.jank)));
      await tester.pumpAndSettle();

      expect(find.byType(JankDetailDialog), findsOneWidget);
      expect(find.text('UI freeze'), findsOneWidget);
      expect(find.textContaining('900ms'), findsWidgets);

      // The correlation is the whole point — a freeze has no stack trace, so
      // the other lanes are the only evidence available.
      expect(find.textContaining('/huge'), findsOneWidget);

      // And it must not overclaim: correlation is not causation, and the dialog
      // says so rather than presenting a list that implies it.
      expect(find.textContaining('Circumstantial'), findsOneWidget);
    });

    testWidgets('the dialog explains why there is no stack trace', (tester) async {
      final start = DateTime.now();
      watchdog.recordFreezeForTesting(
        FreezeEvent(start: start, end: start.add(const Duration(milliseconds: 400)), duration: const Duration(milliseconds: 400)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DevtrayThemeScope(
            theme: const DevtrayTheme(),
            child: Scaffold(
              body: SizedBox(height: 400, child: Builder(builder: const TimelineDebugPage().build)),
            ),
          ),
        ),
      );
      await tester.pump();

      final box = tester.getRect(find.byType(CustomPaint).last);
      await tester.tapAt(Offset(box.right - 6, box.top + TimelineMetrics.laneCenter(TimelineLane.jank)));
      await tester.pumpAndSettle();

      // The first thing anyone looks for here is a stack trace. Saying why
      // there isn't one beats leaving them to conclude the tool is broken.
      expect(find.textContaining('No stack trace'), findsOneWidget);
    });

    test('freezes outside the window are excluded', () {
      watchdog.recordFreezeForTesting(
        FreezeEvent(start: DateTime(2020), end: DateTime(2020, 1, 1, 0, 0, 1), duration: const Duration(seconds: 1)),
      );

      final events = collectTimelineEvents(
        from: DateTime.now().subtract(const Duration(seconds: 5)),
        to: DateTime.now(),
      );

      expect(events.where((e) => e.lane == TimelineLane.jank), isEmpty);
    });
  });
}
