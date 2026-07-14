import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';

import '../core/debug_overlay_kill_switch.dart';
import 'debug_inspectable.dart';

/// One recorded change to a bloc/cubit.
class BlocChangeEntry {
  final int id;
  final DateTime time;

  /// Null for a plain cubit `emit` — only blocs have events.
  final Object? event;

  final Object? from;
  final Object? to;

  const BlocChangeEntry({
    required this.id,
    required this.time,
    required this.from,
    required this.to,
    this.event,
  });
}

/// A live bloc/cubit the observer has seen.
///
/// Held by [identityHashCode], not by type — an app can have several instances
/// of the same cubit alive at once (one per screen), and they must not be
/// conflated.
class TrackedBloc {
  final int id;
  final String type;
  final DateTime created;

  /// Newest first, capped.
  final List<BlocChangeEntry> changes = [];

  Object? state;
  Object? error;
  StackTrace? stackTrace;
  DateTime? closed;

  bool get isClosed => closed != null;

  /// **Weak** on purpose.
  ///
  /// Reading a cubit's non-state fields means calling into the live instance, so
  /// we need a handle on it. A strong one would make this debug tool the thing
  /// keeping every cubit your app ever created alive — the exact leak the tool
  /// exists to help you find.
  ///
  /// Null once the app has dropped its own reference and the GC has run. The
  /// recorded state and transitions survive; only the *live* field read stops
  /// working, which is correct — there's nothing left to read.
  final WeakReference<BlocBase<dynamic>>? ref;

  TrackedBloc({
    required this.id,
    required this.type,
    required this.created,
    required this.state,
    this.ref,
  });
}

/// Records every bloc/cubit the app creates, its current state, and its
/// transition history.
///
/// Install the observer to feed it:
///
/// ```dart
/// Bloc.observer = DebugBlocObserver();
/// ```
///
/// Nothing is captured when [DebugOverlayKillSwitch] is off, so a release build
/// pays nothing but the observer's own (trivial) dispatch.
class BlocStore {
  BlocStore._() {
    DebugOverlayKillSwitch.addDisableListener(clear);
  }
  static final BlocStore instance = BlocStore._();

  /// Extractors for fields that live on the cubit but not in its state.
  ///
  /// Keyed by runtime type name — one registration covers every instance.
  final Map<String, Map<String, Object?> Function(BlocBase<dynamic>)> _inspectors = {};

  /// Show fields a cubit holds **outside its state** — a sync queue, a lookup
  /// map, a retry counter.
  ///
  /// `BlocObserver` only ever gives the overlay `bloc.state`, and Flutter has no
  /// runtime reflection to go find the rest. So you point at them:
  ///
  /// ```dart
  /// BlocStore.instance.inspect<SyncCubit>((c) => {
  ///   'queue': c.queue.length,
  ///   'next': c.queue.firstOrNull,
  ///   'retries': c.retries,
  /// });
  /// ```
  ///
  /// Registered once at startup, applies to every instance of that type, and is
  /// **read fresh on every rebuild** — so the values are live.
  ///
  /// This keeps debug code out of your cubits entirely. If you'd rather put it
  /// in the class, implement [DebugInspectable] instead; a registration here
  /// wins over that, so you can override a cubit's own fields without touching
  /// it.
  void inspect<T extends BlocBase<dynamic>>(Map<String, Object?> Function(T bloc) extract) {
    _inspectors[T.toString()] = (bloc) => extract(bloc as T);
  }

  /// The extra fields for a live bloc, or empty if none are exposed.
  ///
  /// The registry wins over [DebugInspectable] — so an app can override what a
  /// cubit says about itself without editing it.
  Map<String, Object?> fieldsFor(BlocBase<dynamic> bloc) {
    final registered = _inspectors[bloc.runtimeType.toString()];
    if (registered != null) {
      // A bad extractor must not take the debug page down with it.
      try {
        return registered(bloc);
      } catch (e) {
        return {'<extractor threw>': e.toString()};
      }
    }

    if (bloc is DebugInspectable) {
      try {
        return (bloc as DebugInspectable).debugFields;
      } catch (e) {
        return {'<debugFields threw>': e.toString()};
      }
    }

    return const {};
  }

  /// Transitions kept per bloc. The interesting ones are always the most recent.
  int maxChangesPerBloc = 100;

  /// Closed blocs are kept so you can still read what happened before they went
  /// away — but not forever.
  int maxClosedBlocs = 20;

  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  final Map<int, TrackedBloc> _blocs = {};
  int _nextChangeId = 0;

  /// Live blocs first, then recently closed ones. Oldest-created first within
  /// each group, so the list doesn't reshuffle as you watch it.
  List<TrackedBloc> get blocs {
    final all = _blocs.values.toList()
      ..sort((a, b) {
        if (a.isClosed != b.isClosed) return a.isClosed ? 1 : -1;
        return a.created.compareTo(b.created);
      });
    return List.unmodifiable(all);
  }

  void onCreate(BlocBase<dynamic> bloc) {
    if (!DebugOverlayKillSwitch.enabled) return;

    _blocs[identityHashCode(bloc)] = TrackedBloc(
      id: identityHashCode(bloc),
      type: bloc.runtimeType.toString(),
      created: DateTime.now(),
      state: bloc.state,
      ref: WeakReference(bloc),
    );
    tick.value++;
  }

  /// The cubit's non-state fields, read **live** from the instance.
  ///
  /// Empty when nothing is registered for it, or when the instance has been
  /// garbage-collected (see [TrackedBloc.ref]).
  Map<String, Object?> liveFieldsOf(TrackedBloc tracked) {
    final bloc = tracked.ref?.target;
    return bloc == null ? const {} : fieldsFor(bloc);
  }

  /// The event from `onTransition`, waiting for the `onChange` it belongs to.
  ///
  /// A Bloc calls `onTransition` **then** `emit` (which fires `onChange`) — see
  /// `Bloc._on`'s `onEmit`. So the event arrives *before* the change it caused,
  /// and has to be held for it. Getting this backwards would staple each event
  /// onto the previous transition.
  ///
  /// Keyed by bloc, because two blocs can be mid-transition at once.
  final Map<int, Object?> _pendingEvents = {};

  void onTransition(Bloc<dynamic, dynamic> bloc, Transition<dynamic, dynamic> transition) {
    if (!DebugOverlayKillSwitch.enabled) return;
    _pendingEvents[identityHashCode(bloc)] = transition.event;
  }

  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    if (!DebugOverlayKillSwitch.enabled) return;

    // Present for a Bloc (set by onTransition just now), absent for a plain
    // Cubit — which has no events at all.
    final event = _pendingEvents.remove(identityHashCode(bloc));

    // A bloc created before the observer was installed is still worth tracking —
    // register it lazily rather than dropping its changes on the floor.
    final tracked = _blocs.putIfAbsent(
      identityHashCode(bloc),
      () => TrackedBloc(
        id: identityHashCode(bloc),
        type: bloc.runtimeType.toString(),
        created: DateTime.now(),
        state: change.currentState,
        ref: WeakReference(bloc),
      ),
    );

    tracked.state = change.nextState;
    tracked.changes.insert(
      0,
      BlocChangeEntry(
        id: _nextChangeId++,
        time: DateTime.now(),
        from: change.currentState,
        to: change.nextState,
        event: event,
      ),
    );

    while (tracked.changes.length > maxChangesPerBloc) {
      tracked.changes.removeLast();
    }
    tick.value++;
  }

  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    if (!DebugOverlayKillSwitch.enabled) return;

    final tracked = _blocs[identityHashCode(bloc)];
    if (tracked == null) return;

    tracked
      ..error = error
      ..stackTrace = stackTrace;
    tick.value++;
  }

  void onClose(BlocBase<dynamic> bloc) {
    if (!DebugOverlayKillSwitch.enabled) return;

    // Don't leak a pending event for a bloc that's going away.
    _pendingEvents.remove(identityHashCode(bloc));

    final tracked = _blocs[identityHashCode(bloc)];
    if (tracked == null) return;

    tracked.closed = DateTime.now();
    _evictOldClosed();
    tick.value++;
  }

  /// Keeps closed blocs around — you often want to see what a cubit did just
  /// before the screen that owned it was popped — but caps how many.
  void _evictOldClosed() {
    final closed = _blocs.values.where((b) => b.isClosed).toList()..sort((a, b) => a.closed!.compareTo(b.closed!));

    for (var i = 0; i < closed.length - maxClosedBlocs; i++) {
      _blocs.remove(closed[i].id);
    }
  }

  void clear() {
    _blocs.clear();
    _pendingEvents.clear();
    tick.value++;
  }

  /// Drops every [inspect] registration. Mostly for tests — the store is a
  /// singleton, so a registration would otherwise leak into the next one.
  @visibleForTesting
  void clearInspectors() => _inspectors.clear();

  /// Drops the closed ones, keeping what's live.
  void clearClosed() {
    _blocs.removeWhere((_, b) => b.isClosed);
    tick.value++;
  }
}

/// Feeds [BlocStore]. Install it once:
///
/// ```dart
/// Bloc.observer = DebugBlocObserver();
/// ```
///
/// Chains to an existing observer if you already have one, so your own logging
/// keeps working:
///
/// ```dart
/// Bloc.observer = DebugBlocObserver(next: MyObserver());
/// ```
class DebugBlocObserver extends BlocObserver {
  final BlocObserver? next;

  const DebugBlocObserver({this.next});

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    BlocStore.instance.onCreate(bloc);
    next?.onCreate(bloc);
    super.onCreate(bloc);
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    BlocStore.instance.onChange(bloc, change);
    next?.onChange(bloc, change);
    super.onChange(bloc, change);
  }

  @override
  void onTransition(Bloc<dynamic, dynamic> bloc, Transition<dynamic, dynamic> transition) {
    // A Bloc fires onTransition and THEN onChange for the same state change.
    // Only onTransition carries the event, so it's stashed here and picked up by
    // the onChange that follows — recording the change in both places would log
    // every bloc transition twice.
    BlocStore.instance.onTransition(bloc, transition);
    next?.onTransition(bloc, transition);
    super.onTransition(bloc, transition);
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    BlocStore.instance.onError(bloc, error, stackTrace);
    next?.onError(bloc, error, stackTrace);
    super.onError(bloc, error, stackTrace);
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    BlocStore.instance.onClose(bloc);
    next?.onClose(bloc);
    super.onClose(bloc);
  }
}
