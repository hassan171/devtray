import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/devtray_context.dart';
import '../core/devtray_facade.dart';
import '../logs/devtray_log.dart';

/// One screen the app was on, and for how long.
///
/// A *span*, not an instant. "Which screen was I on when that request failed"
/// is an interval question, and the timeline already draws intervals for
/// requests — so a route lane costs no new painter concept and answers the
/// question directly, rather than making you read between two marks.
class RouteVisit {
  /// Position in the session's navigation order.
  ///
  /// Used to alternate the timeline's shading so contiguous spans have visible
  /// joins. Derived from the visit rather than from draw order, which would
  /// flip every colour as soon as one span scrolled out of the window or a
  /// lane filter changed.
  final int sequence;

  /// The route's name, or a placeholder when it has none.
  ///
  /// A bare `Navigator.push(MaterialPageRoute(builder: ...))` carries no name.
  /// Reporting `<unnamed MaterialPageRoute>` rather than nothing is the honest
  /// option: the gap is visible and fixable by passing `settings:`, where
  /// silently keeping the previous screen would make the field report a page
  /// you had already left.
  final String name;

  /// What kind of route it was — `MaterialPageRoute`, `DialogRoute`.
  final String type;

  /// Whether this sits *over* a screen rather than being one: a dialog, a
  /// bottom sheet, a popup menu.
  ///
  /// Kept separate from the screen itself. A dialog over Checkout leaves the
  /// screen as `checkout` and adds `overlay: DialogRoute` — so a request fired
  /// from behind the dialog still says which page it came from, which is the
  /// thing you wanted to know.
  final bool isOverlay;

  /// The route this was entered *from*, or null for the first one.
  ///
  /// Chronological, not structural: on a pop back to `/` this is `/settings`,
  /// the screen you actually came from, rather than whatever `/` originally sat
  /// beneath. "Where did I just come from" is the question a trail answers, and
  /// the structural stack is already visible in the spans.
  final String? from;

  /// Whether arriving here was a *pop* rather than a push.
  ///
  /// Pairs with [from] to make the direction unambiguous — `/ ← /settings` and
  /// `/settings → /` describe different journeys through the same two screens,
  /// and a trail that showed only the pair could not tell them apart.
  final bool wasReturn;

  final DateTime enteredAt;

  /// When it was popped, or null while it is still on screen.
  DateTime? leftAt;

  RouteVisit({
    required this.sequence,
    required this.name,
    required this.type,
    required this.isOverlay,
    required this.enteredAt,
    this.from,
    this.wasReturn = false,
    this.leftAt,
  });

  /// The journey as one string: `checkout → payment`, or `payment ← receipt`
  /// for a return.
  String get transition {
    if (from == null) return name;
    return wasReturn ? '$name ← $from' : '$from → $name';
  }

  /// Whether this is the route the app is on *now*.
  ///
  /// Not simply `leftAt == null`: pushing a route does not pop the one beneath
  /// it, so every route down the stack would otherwise read as current and the
  /// timeline would draw them all running to the right edge at once. Set by
  /// [DevtrayNav] when a route stops being on top and again when it returns.
  bool get isCurrent => leftAt == null && _onTop;

  /// Whether this route is the topmost of its kind. See [isCurrent].
  bool _onTop = true;
  Duration? get duration => leftAt?.difference(enteredAt);
}

/// The route history, and the current screen.
///
/// Fed by [DevtrayNavObserver]. Separate from the observer so the history
/// survives a Navigator being rebuilt, and so an app with a router that is not
/// a `NavigatorObserver` at all can push into it directly:
///
/// ```dart
/// DevtrayNav.instance.enter('checkout');
/// ```
///
/// That is also the answer for a custom shell — an `IndexedStack` whose body
/// swaps on a tab tap pushes no route, so no observer can see it.
class DevtrayNav {
  DevtrayNav._() {
    Devtray.addDisableListener(clear);
  }
  static final DevtrayNav instance = DevtrayNav._();

  /// The key the current screen is published under, on every log line and
  /// network request.
  static const String screenField = 'screen';

  /// The key a dialog or sheet is published under, while one is up.
  static const String overlayField = 'overlay';

  /// Oldest visits are dropped past this cap.
  int maxVisits = 200;

  final ListQueue<RouteVisit> _visits = ListQueue();

  /// Oldest first, matching the timeline's left-to-right reading order.
  List<RouteVisit> get visits => List.unmodifiable(_visits);

  /// The stack as the Navigator has it, so a pop can restore what was beneath.
  final List<RouteVisit> _stack = [];

  /// The screen currently on top, ignoring any dialog over it.
  RouteVisit? get currentScreen => _stack.lastWhereOrNull((v) => !v.isOverlay);

  /// The dialog or sheet currently up, if any.
  RouteVisit? get currentOverlay => _stack.lastWhereOrNull((v) => v.isOverlay);

  /// Whether a line is logged for each navigation. See [DevtrayNavObserver].
  bool logNavigation = false;

  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// Records entering a route.
  ///
  /// [name] null means an unnamed route — see [RouteVisit.name].
  void enter(String? name, {String type = 'route', bool isOverlay = false}) {
    if (!Devtray.enabled) return;

    final visit = RouteVisit(
      sequence: _nextSequence++,
      name: name ?? '<unnamed $type>',
      type: type,
      isOverlay: isOverlay,
      // Where you came from, chronologically. An overlay does not change the
      // screen, so it records the screen it opened over.
      from: (isOverlay ? currentScreen : _lastEntered)?.name,
      enteredAt: DateTime.now(),
    );

    // The screen you were on has ended.
    //
    // Without this every past visit kept `leftAt == null`, so the timeline drew
    // all of them as still-open spans running to the right edge — stacked on
    // top of each other, darkening as they piled up, and all clamped to the
    // left gutter once their start scrolled out of the window.
    //
    // A pushed route does not end the one beneath structurally (it is still
    // mounted, and `leave` will reopen it as a fresh visit), but its *span* is
    // over: that is not where the app is any more.
    if (!isOverlay) {
      final now = visit.enteredAt;
      for (final v in _stack) {
        v._onTop = false;
        if (!v.isOverlay) v.leftAt ??= now;
      }
      _lastEntered?.leftAt ??= now;
    }

    _stack.add(visit);
    _lastEntered = visit;
    _visits.addLast(visit);
    while (_visits.length > maxVisits) {
      _visits.removeFirst();
    }

    _publish();
    if (logNavigation) {
      DevtrayLog.instance.log(visit.transition, tag: 'nav');
    }
    tick.value++;
  }

  int _nextSequence = 0;

  /// The most recent arrival, so the next one knows where it came from.
  ///
  /// Not `_stack.last`: a pop leaves the stack pointing at the route beneath,
  /// which is where you are going, not where you have been.
  RouteVisit? _lastEntered;

  /// Records leaving the topmost matching route.
  void leave(String? name, {String type = 'route'}) {
    if (!Devtray.enabled) return;

    final resolved = name ?? '<unnamed $type>';
    final index = _stack.lastIndexWhere((v) => v.name == resolved);
    // A pop with nothing to match is not an error: the observer may have been
    // installed after the route was pushed, which is normal at startup.
    if (index == -1) return;

    final left = _stack.removeAt(index)..leftAt = DateTime.now();

    // Returning is its OWN visit, not the old one reopening.
    //
    // A reopened span would have two arrival moments and could carry only one
    // `from`, so the return trip would be unrecorded. As a separate visit the
    // timeline also shows the second stay as its own span, which is what
    // actually happened.
    final beneath = _stack.lastWhereOrNull((v) => !v.isOverlay);
    if (beneath != null && !left.isOverlay) {
      final resumed = RouteVisit(
        sequence: _nextSequence++,
        name: beneath.name,
        type: beneath.type,
        isOverlay: false,
        from: left.name,
        wasReturn: true,
        enteredAt: DateTime.now(),
      );
      // Replace the stack entry, so a later pop leaves *this* span rather than
      // the original one that has already ended.
      _stack[_stack.indexOf(beneath)] = resumed;
      beneath.leftAt ??= resumed.enteredAt;
      _lastEntered = resumed;
      _visits.addLast(resumed);
      while (_visits.length > maxVisits) {
        _visits.removeFirst();
      }
    }

    _publish();
    if (logNavigation) {
      DevtrayLog.instance.log(_lastEntered?.transition ?? '← $resolved', tag: 'nav');
    }
    tick.value++;
  }

  /// Pushes the current screen and overlay into the shared context, so every
  /// log line and network request carries them.
  ///
  /// Written as ambient context rather than an enricher because navigation is
  /// rare and captures are frequent: setting it on each route change is a few
  /// writes a minute, where an enricher would run on every entry forever.
  void _publish() {
    final screen = currentScreen;
    if (screen == null) {
      DevtrayContext.instance.remove(screenField);
    } else {
      DevtrayContext.instance.set(screenField, screen.name);
    }

    final overlay = currentOverlay;
    if (overlay == null) {
      // Removed rather than set to null, so a dismissed dialog leaves no field
      // behind claiming there is one.
      DevtrayContext.instance.remove(overlayField);
    } else {
      DevtrayContext.instance.set(overlayField, overlay.type);
    }
  }

  void clear() {
    _visits.clear();
    _stack.clear();
    // Or the first route after a clear would inherit a `from` pointing at a
    // screen from before it — visible as a phantom transition on the very first
    // line of a fresh session.
    _lastEntered = null;
    _nextSequence = 0;
    DevtrayContext.instance
      ..remove(screenField)
      ..remove(overlayField);
    tick.value++;
  }
}

extension _LastWhereOrNull<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
