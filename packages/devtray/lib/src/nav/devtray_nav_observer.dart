import 'package:flutter/widgets.dart';

import 'devtray_nav.dart';

/// Names a route for the overlay. Return null to fall back to the default.
typedef DevtrayRouteNamer = String? Function(Route<dynamic> route);

/// Tells devtray which screen the app is on, with no call sites of your own.
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [DevtrayNavObserver()],
///   ...
/// )
/// ```
///
/// From then on every log line and every network request carries a `screen`
/// field, so "which screen was I on when that 500 came back" is answered on the
/// entry itself rather than reconstructed from timestamps.
///
/// ## What it can and cannot see
///
/// It sees the **Navigator**. An app whose navigation is a `Navigator` — pushed
/// routes, `pushNamed`, most routers built on top of one — is fully covered.
///
/// It cannot see a custom shell: an `IndexedStack` or a `PageView` whose body
/// swaps on a tab tap pushes no route, so there is nothing to observe. That is
/// not a gap this class can close — only the app knows a swap happened. Tell
/// devtray directly at the point that already knows:
///
/// ```dart
/// onDestinationSelected: (i) {
///   DevtrayNav.instance.enter(_titles[i]);
///   setState(() => _tab = i);
/// }
/// ```
///
/// Both routes feed the same store, so an app that uses a shell *and* pushes
/// routes gets one coherent history.
///
/// ## Unnamed routes
///
/// `Navigator.push(MaterialPageRoute(builder: ...))` carries no name, and there
/// is nothing to read. Such a route reports `<unnamed MaterialPageRoute>` — the
/// gap is visible and fixed by passing `settings:`:
///
/// ```dart
/// MaterialPageRoute(
///   settings: const RouteSettings(name: 'note_editor'),
///   builder: (_) => const NoteEditorScreen(),
/// )
/// ```
///
/// Or supply [nameOf] and derive it however you like.
class DevtrayNavObserver extends NavigatorObserver {
  /// Names a route when its `settings.name` is null, or to override it.
  ///
  /// ```dart
  /// DevtrayNavObserver(
  ///   nameOf: (route) => switch (route.settings.arguments) {
  ///     NoteArgs(:final id) => 'note/$id',
  ///     _ => null,
  ///   },
  /// )
  /// ```
  final DevtrayRouteNamer? nameOf;

  /// Also log a line for each navigation, tagged `nav`.
  ///
  /// Off by default: the `screen` field already puts the route on every entry,
  /// so the lines are largely redundant — and a nav-heavy app would spend a
  /// chunk of the 1000-entry buffer on them. Turn it on when you want the route
  /// trail as its own filterable thing.
  ///
  /// Null means "don't decide" — leave whatever `configure` set. This observer
  /// is constructed when `MaterialApp` builds, which is *after* `configure` has
  /// run, so a non-null default here would silently overwrite
  /// `..navigation(logNavigation: true)` a frame later.
  final bool? logNavigation;

  DevtrayNavObserver({this.nameOf, this.logNavigation}) {
    if (logNavigation != null) {
      DevtrayNav.instance.logNavigation = logNavigation!;
    }
  }

  /// Whether a route sits *over* a screen rather than being one.
  ///
  /// `PageRoute` is the screen-shaped one — full-screen, and what `MaterialApp`
  /// builds for a push. Everything else (dialogs, sheets, popup menus) is drawn
  /// over whatever is beneath, so it is recorded as an overlay and leaves the
  /// screen field pointing at the page it covers.
  static bool _isOverlay(Route<dynamic> route) => route is! PageRoute;

  String? _name(Route<dynamic> route) => nameOf?.call(route) ?? route.settings.name;

  static String _type(Route<dynamic> route) => route.runtimeType.toString();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    DevtrayNav.instance.enter(_name(route), type: _type(route), isOverlay: _isOverlay(route));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    DevtrayNav.instance.leave(_name(route), type: _type(route));
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    DevtrayNav.instance.leave(_name(route), type: _type(route));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    // Order matters: leave first, so the new route is what the screen field
    // ends up reporting rather than being immediately overwritten by the pop.
    if (oldRoute != null) {
      DevtrayNav.instance.leave(_name(oldRoute), type: _type(oldRoute));
    }
    if (newRoute != null) {
      DevtrayNav.instance.enter(_name(newRoute), type: _type(newRoute), isOverlay: _isOverlay(newRoute));
    }
  }
}
