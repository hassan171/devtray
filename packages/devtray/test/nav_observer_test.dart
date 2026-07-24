import 'package:devtray/devtray.dart';
// Not exported from the barrel — the pane is internal to the nav lane.
import 'package:devtray/src/nav/components/route_detail_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An app with the observer installed and one pushable route.
/// [logNavigation] left null means the observer does not decide — matching the
/// real API, where a non-null default would stomp whatever `configure` set.
Widget _app({DevtrayRouteNamer? nameOf, bool? logNavigation}) {
  return MaterialApp(
    navigatorObservers: [DevtrayNavObserver(nameOf: nameOf, logNavigation: logNavigation)],
    routes: {
      '/': (_) => const _Screen('home'),
      '/settings': (_) => const _Screen('settings'),
    },
  );
}

class _Screen extends StatelessWidget {
  final String label;
  const _Screen(this.label);

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(label)));
}

/// The `screen` field as it would land on a log line or a request.
Object? get _screen => DevtrayContext.instance.values[DevtrayNav.screenField];
Object? get _overlay => DevtrayContext.instance.values[DevtrayNav.overlayField];

void main() {
  setUp(() {
    Devtray.reset();
    DevtrayNav.instance
      ..clear()
      // Global and not covered by clear(), which resets the history rather than
      // the settings — so a test that turns it on would leak into every one
      // after it.
      ..logNavigation = false;
    DevtrayLog.instance
      ..clear()
      ..clearContext()
      ..clearEnrichers();
    DevtrayNet.instance.clear();
  });

  group('the screen field', () {
    testWidgets('follows a named push and restores on pop', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(_screen, '/');

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/settings');
      await tester.pumpAndSettle();
      expect(_screen, '/settings');

      navigator.pop();
      await tester.pumpAndSettle();
      // Restored, not cleared: popping returns you to a screen, and leaving the
      // field on the page you just left would misreport every later entry.
      expect(_screen, '/');
    });

    testWidgets('lands on network requests and log lines alike', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/settings');
      await tester.pumpAndSettle();

      Devtray.log('did a thing');
      final request = DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test/x'))!;

      expect(DevtrayLog.instance.entries.first.fields['screen'], '/settings');
      expect(request.fields['screen'], '/settings');
    });

    testWidgets('an unnamed route reports a visible placeholder', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      tester.state<NavigatorState>(find.byType(Navigator)).push(
            MaterialPageRoute<void>(builder: (_) => const _Screen('editor')),
          );
      await tester.pumpAndSettle();

      // Not silence. Keeping the previous screen would make the field report a
      // page you had already left — wrong, and invisible.
      expect(_screen, '<unnamed MaterialPageRoute<void>>');
    });

    testWidgets('nameOf can name a route that has no name of its own', (tester) async {
      await tester.pumpWidget(
        _app(nameOf: (route) => route.settings.arguments is int ? 'note/${route.settings.arguments}' : null),
      );
      await tester.pumpAndSettle();

      tester.state<NavigatorState>(find.byType(Navigator)).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(arguments: 7),
              builder: (_) => const _Screen('editor'),
            ),
          );
      await tester.pumpAndSettle();

      expect(_screen, 'note/7');
    });
  });

  group('from / to', () {
    testWidgets('a push records where it came from', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/settings');
      await tester.pumpAndSettle();

      final visit = DevtrayNav.instance.visits.last;
      expect(visit.from, '/');
      expect(visit.wasReturn, isFalse);
      expect(visit.transition, '/ → /settings');
    });

    test('the first route has no from', () {
      Devtray.screen('home');
      expect(DevtrayNav.instance.visits.single.from, isNull);
      // Not "null → home" — there was nowhere before it.
      expect(DevtrayNav.instance.visits.single.transition, 'home');
    });

    test('direction distinguishes the same pair of screens', () {
      Devtray.screen('checkout');
      Devtray.screen('payment');

      // a → b and b ← a are different journeys through the same two names, and
      // the pair alone cannot tell them apart.
      expect(DevtrayNav.instance.visits.last.transition, 'checkout → payment');
    });

    testWidgets('an overlay records the screen it opened over', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final context = tester.element(find.text('home'));
      showDialog<void>(context: context, builder: (_) => const AlertDialog(content: Text('hi')));
      await tester.pumpAndSettle();

      expect(DevtrayNav.instance.visits.last.from, '/');
    });

    testWidgets('the log line carries the transition, not just the name', (tester) async {
      await tester.pumpWidget(_app(logNavigation: true));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/settings');
      await tester.pumpAndSettle();

      expect(
        DevtrayLog.instance.entries.any((e) => e.tag == 'nav' && e.message == '/ → /settings'),
        isTrue,
      );
    });
  });

  group('overlays', () {
    testWidgets('a dialog leaves the screen alone and adds its own field', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/settings');
      await tester.pumpAndSettle();

      final context = tester.element(find.text('settings'));
      showDialog<void>(context: context, builder: (_) => const AlertDialog(content: Text('hi')));
      await tester.pumpAndSettle();

      // The whole point of keeping them apart: a request fired from behind this
      // dialog still says which page it came from.
      expect(_screen, '/settings');
      expect(_overlay, contains('DialogRoute'));

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      // Removed, not nulled — a dismissed dialog must leave no field behind
      // claiming there is one.
      expect(_overlay, isNull);
      expect(DevtrayContext.instance.values.containsKey(DevtrayNav.overlayField), isFalse);
      expect(_screen, '/settings');
    });
  });

  group('logNavigation', () {
    testWidgets('is off by default', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/settings');
      await tester.pumpAndSettle();

      expect(DevtrayLog.instance.entries.where((e) => e.tag == 'nav'), isEmpty);
    });

    testWidgets('configure wins over the observer default', (tester) async {
      // The observer is constructed when MaterialApp builds, which is AFTER
      // configure has run. A non-null default on the constructor stomped
      // `..navigation(logNavigation: true)` a frame later — silently, since
      // nothing reads the flag back.
      DevtrayNav.instance.logNavigation = true;

      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/settings');
      await tester.pumpAndSettle();

      expect(DevtrayNav.instance.logNavigation, isTrue);
      expect(DevtrayLog.instance.entries.any((e) => e.tag == 'nav'), isTrue);
    });

    testWidgets('logs a line per navigation when asked', (tester) async {
      await tester.pumpWidget(_app(logNavigation: true));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/settings');
      await tester.pumpAndSettle();

      expect(DevtrayLog.instance.entries.any((e) => e.tag == 'nav' && e.message.contains('/settings')), isTrue);
    });
  });

  group('the timeline lane', () {
    testWidgets('draws a visit as a span, open while it is current', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/settings');
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final events = collectTimelineEvents(
        from: now.subtract(const Duration(minutes: 1)),
        to: now.add(const Duration(seconds: 1)),
      );
      final routes = events.where((e) => e.lane == TimelineLane.route).toList();

      // Labelled with the journey, not just the destination — a lane of bare
      // names makes you infer direction from which span sits left.
      expect(routes.map((e) => e.label), containsAll(['/', '/ → /settings']));
      // The current screen has no end yet — same treatment a pending request
      // gets, so it runs to the right edge rather than vanishing.
      expect(routes.firstWhere((e) => e.label == '/ → /settings').isPending, isTrue);
      expect(routes.firstWhere((e) => e.label == '/').isPending, isFalse);
    });

    testWidgets('returning records its own span, so the trip back is visible', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/settings');
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final routes = collectTimelineEvents(
        from: now.subtract(const Duration(minutes: 1)),
        to: now.add(const Duration(seconds: 1)),
      ).where((e) => e.lane == TimelineLane.route).toList();

      // Three spans, not two: the first stay on '/', the trip to '/settings',
      // and the return. Reopening the original span instead would have hidden
      // the return trip — one visit cannot carry two arrivals, so its `from`
      // would have had nowhere to go.
      expect(routes.length, 3);
      expect(routes.last.label, '/ ← /settings');
      expect(routes.last.isPending, isTrue, reason: 'the return is where the app is now');
      expect(_screen, '/');

      final visits = DevtrayNav.instance.visits;
      expect(visits.last.wasReturn, isTrue);
      expect(visits.last.from, '/settings');
      expect(visits.last.transition, '/ ← /settings');
    });

    test('only the current screen stays open, so spans do not stack', () {
      for (final name in ['a', 'b', 'c', 'd', 'e', 'f']) {
        Devtray.screen(name);
      }

      final now = DateTime.now();
      final routes = collectTimelineEvents(
        from: now.subtract(const Duration(seconds: 30)),
        to: now.add(const Duration(seconds: 1)),
      ).where((e) => e.lane == TimelineLane.route).toList();

      // Every past visit used to keep leftAt == null, so all six drew as
      // still-open bars running to the right edge — stacked on top of each
      // other and darkening as they piled up, all clamped to the left gutter
      // once their starts scrolled out of the window.
      expect(routes.where((e) => e.isPending), hasLength(1));
      expect(routes.last.label, 'e → f');

      // And every closed one has a real duration rather than running forever.
      final closed = DevtrayNav.instance.visits.where((v) => !v.isCurrent);
      expect(closed, hasLength(5));
      expect(closed.every((v) => v.duration != null), isTrue);
    });

    test('every route draws as a bar, including the one you are on', () {
      Devtray.screen('home');

      final now = DateTime.now();
      final route = collectTimelineEvents(
        from: now.subtract(const Duration(seconds: 30)),
        to: now.add(const Duration(seconds: 1)),
      ).firstWhere((e) => e.lane == TimelineLane.route);

      // The current route has no `end` yet, so `hasDuration` is false — it used
      // to fall through to the mark path and draw as a small circle sitting on
      // the lane rather than the open span it is.
      expect(route.hasDuration, isFalse);
      expect(drawsAsBar(route), isTrue);
    });

    test('alternation comes from the visit, not from draw order', () {
      for (final name in ['a', 'b', 'c']) {
        Devtray.screen(name);
      }

      final now = DateTime.now();
      final routes = collectTimelineEvents(
        from: now.subtract(const Duration(seconds: 30)),
        to: now.add(const Duration(seconds: 1)),
      ).where((e) => e.lane == TimelineLane.route).toList();

      // Contiguous spans need visible joins, and taking the parity from draw
      // order would flip every colour as soon as one span scrolled out of the
      // window or a lane was muted.
      expect(routes.map((e) => e.sequence), [0, 1, 2]);
      expect(routes.map((e) => e.sequence.isEven), [true, false, true]);
    });

    testWidgets('can be muted like any other lane', (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final events = collectTimelineEvents(
        from: now.subtract(const Duration(minutes: 1)),
        to: now,
        includeRoutes: false,
      );

      expect(events.where((e) => e.lane == TimelineLane.route), isEmpty);
    });
  });

  group('the detail dialog', () {
    testWidgets('a route visit has a detail view of its own', (tester) async {
      // The lane was added without one, so tapping a nav span opened a dialog
      // containing literally nothing — the switch fell through to a
      // SizedBox.shrink().
      Devtray.screen('checkout');
      final visit = DevtrayNav.instance.visits.single;

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RouteDetailPane(visit: visit))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('checkout'), findsWidgets);
      expect(find.text('SCREEN'), findsOneWidget);
      expect(find.textContaining('still open'), findsOneWidget);
    });

    testWidgets('the timeline dispatches a route source to RouteDetailPane', (tester) async {
      // The real dispatch the dialog performs, not a copy of it. The route lane
      // shipped without its case, and the only symptom was a dialog containing
      // nothing — a silent fall-through no test could reach.
      Devtray.screen('checkout');

      final now = DateTime.now();
      final event = collectTimelineEvents(
        from: now.subtract(const Duration(seconds: 30)),
        to: now.add(const Duration(seconds: 1)),
      ).firstWhere((e) => e.lane == TimelineLane.route);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: timelineDetailFor(event.source, onBack: () {}, onRefresh: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RouteDetailPane), findsOneWidget);
      expect(find.textContaining('No detail view'), findsNothing);
    });

    testWidgets('an overlay visit says it does not change the screen', (tester) async {
      DevtrayNav.instance.enter('sheet', type: 'ModalBottomSheetRoute', isOverlay: true);
      final visit = DevtrayNav.instance.visits.single;

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RouteDetailPane(visit: visit))),
      );
      await tester.pumpAndSettle();

      expect(find.text('OVERLAY'), findsOneWidget);
      expect(find.textContaining('does not change'), findsOneWidget);
    });
  });

  group('Devtray.screen', () {
    test('covers a custom shell the observer cannot see', () {
      // An IndexedStack swap pushes no route, so nothing can observe it. This
      // is the escape hatch, and it feeds the same history.
      Devtray.screen('notes');
      expect(_screen, 'notes');

      Devtray.screen('profile');
      expect(_screen, 'profile');
      expect(DevtrayNav.instance.visits.map((v) => v.name), ['notes', 'profile']);
    });
  });

  group('the kill switch', () {
    test('records nothing while capture is off', () {
      Devtray.enabled = false;
      addTearDown(Devtray.reset);

      Devtray.screen('checkout');

      expect(DevtrayNav.instance.visits, isEmpty);
      expect(_screen, isNull);
    });
  });
}
