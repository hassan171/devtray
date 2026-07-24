import 'package:flutter/foundation.dart';

/// A callback the host app registers to observe one captured item.
///
/// The counterpart to the `tick` notifiers, which say only *that* something
/// changed. This carries the thing itself, so a listener can act on it —
/// forward an error to a crash reporter, count a failed request, react to a
/// 401 — without diffing a buffer to work out what arrived.
typedef DevtrayListener<T> = void Function(T item);

/// Removes a registration. Returned by every `on…` method.
///
/// A returned disposer rather than a `removeListener(fn)` pair because the
/// common registration is a closure written inline, and removing it later would
/// otherwise mean hoisting it to a field purely so there is something to pass
/// back. Holding the disposer is the same one field, and it cannot be the
/// *wrong* one.
typedef DevtrayUnsubscribe = void Function();

/// The listener list every store keeps, and the guarantees that come with it.
///
/// Pulled out rather than repeated six times because the awkward parts —
/// surviving a throwing listener, tolerating a listener that unsubscribes while
/// being notified — are identical everywhere and are exactly the parts that are
/// wrong when hand-rolled.
class DevtrayListeners<T> {
  DevtrayListeners(this._label);

  /// Names this list in the error line a throwing listener produces, so the log
  /// says *which* callback broke rather than just that one did.
  final String _label;

  final List<DevtrayListener<T>> _listeners = [];

  bool get isEmpty => _listeners.isEmpty;

  /// Registers [listener]; call the result to unregister.
  ///
  /// Registering the same closure twice registers it twice — it will be called
  /// twice, and each disposer removes one. This matches `ChangeNotifier` and is
  /// the honest behaviour: closures have no identity worth deduplicating on, and
  /// silently dropping the second registration would make one of the two
  /// disposers a no-op that appears to work.
  DevtrayUnsubscribe add(DevtrayListener<T> listener) {
    _listeners.add(listener);
    var removed = false;
    return () {
      // Guarded so calling the disposer twice cannot remove a *different*
      // registration of the same closure.
      if (removed) return;
      removed = true;
      _listeners.remove(listener);
    };
  }

  /// Drops every registration.
  ///
  /// Mostly for tests: the stores are singletons, so a listener registered in
  /// one test would otherwise fire for every test after it.
  void clear() => _listeners.clear();

  /// Calls every listener with [item].
  ///
  /// **Synchronous, and after the item is stored.** Synchronous because the
  /// point is to react to the thing that just happened — deferring would reorder
  /// callbacks against the capture that triggered them, and a listener that
  /// wants to get off the current frame can schedule that itself. After storing,
  /// because a listener that throws must not cost you the entry it was watching.
  ///
  /// A throwing listener is caught and reported as an ordinary error line, then
  /// the remaining listeners still run. One broken callback is a bug in that
  /// callback; it is not a reason for the other five to be skipped, and it is
  /// certainly not a reason for the app being debugged to crash.
  void notify(T item) {
    // Iterated over a copy: a listener is allowed to unsubscribe itself (or
    // another) from inside the callback, which would otherwise mutate the list
    // mid-iteration and throw.
    for (final listener in List<DevtrayListener<T>>.of(_listeners)) {
      try {
        listener(item);
      } catch (e, stack) {
        _reportBrokenListener(e, stack);
      }
    }
  }

  /// How a broken listener is reported.
  ///
  /// Injected rather than imported so this file carries no dependency on the log
  /// store — which depends on *this* one, and a cycle between the two would make
  /// the singleton initialization order load-bearing.
  ///
  /// Assigned by `DevtrayLog`'s own library, not by its constructor: a listener
  /// on some *other* store can throw before anything has ever been logged, and a
  /// reporter installed by `DevtrayLog._()` would still be null at that point.
  ///
  /// Deliberately not `DevtrayLog.report`: report() badges the launcher and is
  /// itself observed by the error listeners, so a broken *error* listener would
  /// be re-entered by its own failure. A plain error line records it without
  /// that loop.
  static void Function(String message, StackTrace stack)? onListenerError;

  void _reportBrokenListener(Object error, StackTrace stack) {
    // Guards the remaining re-entrancy: reporting runs the *log* listeners, and
    // a broken one of those throws again on the way out.
    if (_reporting) return;
    _reporting = true;
    try {
      final message = 'A $_label listener threw and was skipped: $error';
      final report = onListenerError;
      if (report != null) {
        report(message, stack);
      } else {
        // No reporter wired yet. Still say it out loud rather than swallowing
        // it — a callback silently not running is the worst possible failure
        // mode for a feature whose whole job is to run callbacks.
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack, library: 'devtray', context: ErrorDescription(message)),
        );
      }
    } catch (_) {
      // The reporter itself failed. There is nowhere left to put this.
    } finally {
      _reporting = false;
    }
  }

  bool _reporting = false;
}
