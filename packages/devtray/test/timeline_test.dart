import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final logs = LogStore.instance;
  final network = NetworkLogStore.instance;
  final state = StateInspector.instance;

  setUp(() {
    logs
      ..clear()
      ..clearContext()
      ..clearEnrichers();
    network.clear();
    state.clear();
  });

  group('collecting events', () {
    test('reads all three stores onto one axis', () {
      final now = DateTime.now();

      logs.log('hello');
      final req = network.add(method: 'GET', uri: Uri.parse('https://api.test/items'));
      network.complete(req!.id, status: NetworkLogStatus.success, statusCode: 200);
      state.record(1, type: 'CartCubit', from: 0, to: 1);

      final events = collectTimelineEvents(
        from: now.subtract(const Duration(seconds: 5)),
        to: now.add(const Duration(seconds: 5)),
      );

      expect(events.map((e) => e.lane).toSet(), {
        TimelineLane.network,
        TimelineLane.log,
        TimelineLane.state,
      });
    });

    test('excludes events outside the window', () {
      logs.log('right now');

      // A window that ended before anything happened.
      final events = collectTimelineEvents(
        from: DateTime(2020),
        to: DateTime(2020, 1, 1, 0, 0, 30),
      );

      expect(events, isEmpty);
    });

    test('includes a request that STARTED before the window but is still running', () {
      final req = network.add(method: 'GET', uri: Uri.parse('https://api.test/slow'));
      expect(req, isNotNull);

      // Window opens after the request began. Overlap, not containment — a
      // long request still in flight is exactly what you opened the timeline
      // to look at, so starting early must not hide it.
      final events = collectTimelineEvents(
        from: DateTime.now().add(const Duration(seconds: 1)),
        to: DateTime.now().add(const Duration(seconds: 10)),
      );

      expect(events.where((e) => e.lane == TimelineLane.network), hasLength(1));
      expect(events.first.isPending, isTrue);
    });

    test('lane filters exclude at collection time, not at paint time', () {
      logs.log('a log');
      final req = network.add(method: 'GET', uri: Uri.parse('https://api.test/x'));
      network.complete(req!.id, status: NetworkLogStatus.success, statusCode: 200);

      final now = DateTime.now();
      final events = collectTimelineEvents(
        from: now.subtract(const Duration(seconds: 5)),
        to: now.add(const Duration(seconds: 5)),
        includeLogs: false,
      );

      expect(events.every((e) => e.lane != TimelineLane.log), isTrue);
      expect(events, isNotEmpty, reason: 'the network event survives');
    });

    test('a failed request is marked as an error', () {
      final req = network.add(method: 'GET', uri: Uri.parse('https://api.test/boom'));
      network.complete(req!.id, status: NetworkLogStatus.failed, statusCode: 500);

      final now = DateTime.now();
      final events = collectTimelineEvents(
        from: now.subtract(const Duration(seconds: 5)),
        to: now.add(const Duration(seconds: 5)),
        includeLogs: false,
        includeState: false,
      );

      expect(events.single.isError, isTrue);
      expect(events.single.label, contains('500'));
    });

    test('a pending request has no end but reports one for layout', () {
      final req = network.add(method: 'GET', uri: Uri.parse('https://api.test/wait'));
      expect(req, isNotNull);

      final now = DateTime.now();
      final events = collectTimelineEvents(
        from: now.subtract(const Duration(seconds: 5)),
        to: now.add(const Duration(seconds: 5)),
        includeLogs: false,
        includeState: false,
      );

      final event = events.single;
      expect(event.end, isNull);
      expect(event.hasDuration, isFalse);

      // Still needs a right edge to draw, or an in-flight request would be
      // invisible until it completed.
      final later = event.start.add(const Duration(seconds: 2));
      expect(event.effectiveEnd(later), later);

      // ...but never one BEFORE its start. A `now` captured earlier than the
      // request began would otherwise give the bar a negative width.
      final earlier = event.start.subtract(const Duration(seconds: 2));
      expect(event.effectiveEnd(earlier), event.start);
    });
  });

  group('hit testing', () {
    final from = DateTime(2026, 7, 19, 14, 30);
    final to = DateTime(2026, 7, 19, 14, 30, 30);

    TimelineEvent markAt(DateTime t, TimelineLane lane) => TimelineEvent(
      lane: lane,
      start: t,
      label: 'x',
      source: Object(),
    );

    test('finds a mark under the tap', () {
      final event = markAt(from.add(const Duration(seconds: 15)), TimelineLane.log);
      const width = 400.0;

      final x = TimelineMetrics.xFor(event.start, from, to, width);
      final y = TimelineMetrics.laneCenter(TimelineLane.log);

      final hit = hitTestTimeline(
        position: Offset(x, y),
        events: [event],
        from: from,
        to: to,
        width: width,
      );

      expect(identical(hit, event), isTrue);
    });

    test('misses when the tap is in a different lane', () {
      final event = markAt(from.add(const Duration(seconds: 15)), TimelineLane.log);
      const width = 400.0;

      final x = TimelineMetrics.xFor(event.start, from, to, width);
      // Same x, but the state lane.
      final y = TimelineMetrics.laneCenter(TimelineLane.state);

      expect(
        hitTestTimeline(position: Offset(x, y), events: [event], from: from, to: to, width: width),
        isNull,
        reason: 'lanes must not steal each other\'s taps',
      );
    });

    test('misses when the tap is far along the axis', () {
      final event = markAt(from.add(const Duration(seconds: 5)), TimelineLane.log);
      const width = 400.0;

      final y = TimelineMetrics.laneCenter(TimelineLane.log);
      final farX = TimelineMetrics.xFor(from.add(const Duration(seconds: 25)), from, to, width);

      expect(
        hitTestTimeline(position: Offset(farX, y), events: [event], from: from, to: to, width: width),
        isNull,
      );
    });

    test('a very short request is still tappable', () {
      // 2ms — narrower than the minimum bar width, which is why the painter
      // floors it. The hit test has to agree, or you can see a bar you cannot
      // touch.
      final event = TimelineEvent(
        lane: TimelineLane.network,
        start: from.add(const Duration(seconds: 10)),
        end: from.add(const Duration(seconds: 10, milliseconds: 2)),
        label: 'GET /fast',
        source: Object(),
      );
      const width = 400.0;

      final x = TimelineMetrics.xFor(event.start, from, to, width);
      final y = TimelineMetrics.laneCenter(TimelineLane.network);

      expect(
        identical(hitTestTimeline(position: Offset(x, y), events: [event], from: from, to: to, width: width), event),
        isTrue,
      );
    });

    test('a tap inside a long bar hits it anywhere along its length', () {
      final event = TimelineEvent(
        lane: TimelineLane.network,
        start: from.add(const Duration(seconds: 5)),
        end: from.add(const Duration(seconds: 20)),
        label: 'GET /slow',
        source: Object(),
      );
      const width = 400.0;

      final middle = TimelineMetrics.xFor(from.add(const Duration(seconds: 12)), from, to, width);
      final y = TimelineMetrics.laneCenter(TimelineLane.network);

      expect(
        identical(hitTestTimeline(position: Offset(middle, y), events: [event], from: from, to: to, width: width), event),
        isTrue,
      );
    });

    test('picks the nearest of two close marks', () {
      final near = markAt(from.add(const Duration(seconds: 15)), TimelineLane.log);
      final far = markAt(from.add(const Duration(seconds: 16)), TimelineLane.log);
      const width = 4000.0; // wide, so a second is many pixels apart

      final x = TimelineMetrics.xFor(near.start, from, to, width);
      final y = TimelineMetrics.laneCenter(TimelineLane.log);

      expect(
        identical(hitTestTimeline(position: Offset(x, y), events: [near, far], from: from, to: to, width: width), near),
        isTrue,
      );
    });
  });

  group('the page', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        home: DevtrayThemeScope(
          theme: const DevtrayTheme(),
          child: Scaffold(
            body: SizedBox(height: 400, child: Builder(builder: const TimelineDebugPage().build)),
          ),
        ),
      ),
    );

    testWidgets('starts live', (tester) async {
      await pump(tester);
      await tester.pump();

      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('PAUSED'), findsNothing);
    });

    testWidgets('tapping the plot freezes it', (tester) async {
      logs.log('something');
      await pump(tester);
      await tester.pump();

      // Even an empty-space tap pauses — useful the moment something
      // interesting scrolls past.
      await tester.tapAt(tester.getCenter(find.byType(CustomPaint).last));
      await tester.pumpAndSettle();

      expect(find.text('PAUSED'), findsOneWidget);
    });

    testWidgets('the live/paused badge toggles both ways', (tester) async {
      await pump(tester);
      await tester.pump();

      await tester.tap(find.text('LIVE'));
      await tester.pumpAndSettle();
      expect(find.text('PAUSED'), findsOneWidget);

      await tester.tap(find.text('PAUSED'));
      await tester.pumpAndSettle();
      expect(find.text('LIVE'), findsOneWidget);
    });

    testWidgets('lane chips mute their lane', (tester) async {
      final req = network.add(method: 'GET', uri: Uri.parse('https://api.test/x'));
      network.complete(req!.id, status: NetworkLogStatus.success, statusCode: 200);
      logs.log('a log line');

      await pump(tester);
      await tester.pump();

      expect(find.textContaining(' in 30s'), findsOneWidget);

      await tester.tap(find.text('net'));
      await tester.pumpAndSettle();

      // The count in the toolbar is the observable: muting removes events from
      // collection rather than hiding them at paint time.
      expect(find.text('1 in 30s'), findsOneWidget);
    });

    testWidgets('the gesture area is the painted area, not a taller box', (tester) async {
      await pump(tester);
      await tester.pump();

      final painted = tester.getSize(find.byType(CustomPaint).last);

      // The bug this guards: the plot was inside an Expanded, so the box
      // stretched to fill a 400px page while the lanes drew ~120px at the top.
      // Drags in the empty space below hit a gesture detector that was there,
      // over a chart that wasn't — which reads as "the timeline doesn't
      // scroll".
      // Within a few pixels: the container's 1px border insets its child.
      // The point is that it is ~120 and not ~400, which is what Expanded gave.
      expect(
        painted.height,
        closeTo(TimelineMetrics.totalHeight, 4.0),
        reason: 'the plot must be as tall as the lanes it draws, not the page',
      );
    });

    testWidgets('dragging scrolls through history and freezes', (tester) async {
      await pump(tester);
      await tester.pump();
      expect(find.textContaining('in 30s'), findsOneWidget);

      // Drag right: back in time. The window is no longer anchored to now.
      await tester.drag(find.byType(CustomPaint).last, const Offset(120, 0));
      await tester.pumpAndSettle();

      expect(find.text('PAUSED'), findsOneWidget, reason: 'you cannot scroll a window that is also sliding');
      // Span is unchanged by a pan — only the end moved.
      expect(find.textContaining('in 30s'), findsOneWidget);
    });

    /// The toolbar's "N in <span>" readout, which is how the current zoom is
    /// observable from a test.
    String spanReadout(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((s) => s.contains(' in '))
        .split(' in ')
        .last;

    testWidgets('a zoom preset changes the span', (tester) async {
      await pump(tester);
      await tester.pump();
      expect(spanReadout(tester), '30s');

      await tester.tap(find.text('1s'));
      await tester.pumpAndSettle();

      expect(spanReadout(tester), '1s');
    });

    testWidgets('the preset matching the current span is the active one', (tester) async {
      await pump(tester);
      await tester.pump();

      // The default window is 30s, so that chip should already be active —
      // "nothing highlighted" would read as broken.
      final active = tester.widget<Container>(
        find
            .ancestor(of: find.text('30s'), matching: find.byType(Container))
            .first,
      );
      final decoration = active.decoration! as BoxDecoration;
      expect(decoration.color, isNot(Colors.transparent), reason: 'the active preset is tinted');
    });

    testWidgets('zooming does NOT pause — watching the last second live is reasonable', (tester) async {
      await pump(tester);
      await tester.pump();
      expect(find.text('LIVE'), findsOneWidget);

      await tester.tap(find.text('1s'));
      await tester.pumpAndSettle();

      // Forcing a pause here would make the live view unusable at close range,
      // which is exactly where a 1s window is worth having.
      expect(find.text('LIVE'), findsOneWidget);
      expect(spanReadout(tester), '1s');
    });

    testWidgets('toggling live/paused keeps the zoom', (tester) async {
      await pump(tester);
      await tester.pump();

      await tester.tap(find.text('2s'));
      await tester.pumpAndSettle();
      expect(spanReadout(tester), '2s', reason: 'precondition: we are zoomed');

      // Round-trip: pause, then back to live.
      await tester.tap(find.text('LIVE'));
      await tester.pumpAndSettle();
      expect(find.text('PAUSED'), findsOneWidget);

      await tester.tap(find.text('PAUSED'));
      await tester.pumpAndSettle();
      expect(find.text('LIVE'), findsOneWidget);

      // The workflow this protects: pick a scale, pause to read, resume to
      // watch more traffic AT THAT SCALE. Resetting on resume made the toggle
      // hostile to the thing it exists for.
      expect(spanReadout(tester), '2s', reason: 'resuming must not throw away the zoom');
    });

    testWidgets('the presets span sub-second to minutes', (tester) async {
      await pump(tester);
      await tester.pump();

      // The ends are the point: 100ms is inside one frame's work, 10m is the
      // whole session. Six 5x-apart presets left real gaps in between.
      await tester.tap(find.text('100ms'));
      await tester.pumpAndSettle();
      expect(spanReadout(tester), '100ms');

      await tester.dragUntilVisible(
        find.text('10m'),
        find.byType(SingleChildScrollView).last,
        const Offset(-60, 0),
      );
      await tester.tap(find.text('10m'));
      await tester.pumpAndSettle();
      expect(spanReadout(tester), '10m');
    });

    group('tapping a mark', () {
      /// Taps the first mark in a lane by computing where the painter put it,
      /// rather than guessing at pixels.
      Future<void> tapMark(WidgetTester tester, TimelineLane lane) async {
        final plot = find.byType(CustomPaint).last;
        final box = tester.getRect(plot);
        // Marks land at the right-hand edge of a live window, since everything
        // was logged a moment ago. Come in slightly from the edge.
        final x = box.right - 6;
        final y = box.top + TimelineMetrics.laneCenter(lane);
        await tester.tapAt(Offset(x, y));
        await tester.pumpAndSettle();
      }

      testWidgets('a request opens a dialog, not a sheet', (tester) async {
        final req = network.add(method: 'GET', uri: Uri.parse('https://api.test/items'));
        network.complete(req!.id, status: NetworkLogStatus.success, statusCode: 200);

        await pump(tester);
        await tester.pump();
        await tapMark(tester, TimelineLane.network);

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
      });

      testWidgets('a log opens a dialog', (tester) async {
        logs.log('a line to tap');

        await pump(tester);
        await tester.pump();
        await tapMark(tester, TimelineLane.log);

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
      });

      testWidgets('a state change opens a dialog', (tester) async {
        state.record(1, type: 'CartCubit', from: 0, to: 1);

        await pump(tester);
        await tester.pump();
        await tapMark(tester, TimelineLane.state);

        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
      });
    });

    testWidgets('says so when the window is empty', (tester) async {
      await pump(tester);
      await tester.pump();

      expect(find.textContaining('Nothing in this window'), findsOneWidget);
    });

    testWidgets('does not tick while paused', (tester) async {
      await pump(tester);
      await tester.pump();

      await tester.tap(find.text('LIVE'));
      await tester.pumpAndSettle();

      // A paused timeline is a still image. If the ticker were still running,
      // pumpAndSettle would never settle.
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(find.text('PAUSED'), findsOneWidget);
    });
  });
}
