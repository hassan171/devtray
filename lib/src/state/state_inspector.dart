import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/debug_overlay_kill_switch.dart';
import 'debug_inspectable.dart';

/// One recorded change to a tracked state source.
class StateChangeEntry {
  final int id;
  final DateTime time;

  /// What triggered the change, if anything carries one — a bloc event, a
  /// Redux action, an explicit label. Null for a plain value change (a cubit
  /// `emit`, a `ValueNotifier` set).
  final Object? event;

  final Object? from;
  final Object? to;

  const StateChangeEntry({
    required this.id,
    required this.time,
    required this.from,
    required this.to,
    this.event,
  });
}

/// A live state source the inspector has seen — a cubit, a bloc, a Riverpod
/// provider, a `ValueNotifier`, anything.
///
/// Held by a caller-supplied [id] (see [StateInspector.record]) rather than by
/// type: an app can have several instances of the same type alive at once (one
/// per screen), and they must not be conflated. For bloc, the adapter uses
/// `identityHashCode`.
class TrackedSource {
  final int id;
  final String type;
  final DateTime created;

  /// Newest first, capped.
  final List<StateChangeEntry> changes = [];

  Object? state;
  Object? error;
  StackTrace? stackTrace;
  DateTime? closed;

  bool get isClosed => closed != null;

  /// **Weak** on purpose.
  ///
  /// Reading a source's non-state fields (see [StateInspector.inspect]) means
  /// calling into the live instance, so we need a handle on it. A strong one
  /// would make this debug tool the thing keeping every state object your app
  /// ever created alive — the exact leak the tool exists to help you find.
  ///
  /// Null once the app has dropped its own reference and the GC has run. The
  /// recorded state and changes survive; only the *live* field read stops
  /// working, which is correct — there's nothing left to read.
  final WeakReference<Object>? ref;

  TrackedSource({
    required this.id,
    required this.type,
    required this.created,
    required this.state,
    this.ref,
  });
}

/// Records every state source the app creates, its current state, and its
/// change history — independent of any particular state-management library.
///
/// Adapters push into it. The bundled bloc adapter installs as:
///
/// ```dart
/// Bloc.observer = DebugBlocObserver();
/// ```
///
/// Any other library feeds it directly — see the push API ([record],
/// [recordError], [recordCreate], [recordClose]). Ready-made glue for Riverpod,
/// `ValueNotifier`, and plain `setState` lives in `state_bridge.dart`.
///
/// Nothing is captured when [DebugOverlayKillSwitch] is off, so a release build
/// pays nothing but the adapter's own (trivial) dispatch.
class StateInspector {
  StateInspector._() {
    DebugOverlayKillSwitch.addDisableListener(clear);
  }
  static final StateInspector instance = StateInspector._();

  /// Extractors for fields that live on the source but not in its state.
  ///
  /// Keyed by runtime type name — one registration covers every instance.
  final Map<String, Map<String, Object?> Function(Object)> _inspectors = {};

  /// Show fields a source holds **outside its state** — a sync queue, a lookup
  /// map, a retry counter.
  ///
  /// The inspector only ever sees the current state value, and Flutter has no
  /// runtime reflection to go find the rest. So you point at them:
  ///
  /// ```dart
  /// StateInspector.instance.inspect<SyncCubit>((c) => {
  ///   'queue': c.queue.length,
  ///   'next': c.queue.firstOrNull,
  ///   'retries': c.retries,
  /// });
  /// ```
  ///
  /// Registered once at startup, applies to every instance of that type, and is
  /// **read fresh on every rebuild** — so the values are live.
  ///
  /// This keeps debug code out of your classes entirely. If you'd rather put it
  /// in the class, implement [DebugInspectable] instead; a registration here
  /// wins over that, so you can override a source's own fields without touching
  /// it.
  void inspect<T extends Object>(Map<String, Object?> Function(T source) extract) {
    _inspectors[T.toString()] = (source) => extract(source as T);
  }

  /// The extra fields for a live source, or empty if none are exposed.
  ///
  /// The registry wins over [DebugInspectable] — so an app can override what a
  /// source says about itself without editing it.
  Map<String, Object?> fieldsFor(Object source) {
    final registered = _inspectors[source.runtimeType.toString()];
    if (registered != null) {
      // A bad extractor must not take the debug page down with it.
      try {
        return registered(source);
      } catch (e) {
        return {'<extractor threw>': e.toString()};
      }
    }

    if (source is DebugInspectable) {
      try {
        return source.debugFields;
      } catch (e) {
        return {'<debugFields threw>': e.toString()};
      }
    }

    return const {};
  }

  /// Display overrides for a state value, keyed by the state's runtime type.
  final Map<String, String Function(Object)> _formatters = {};

  /// Control how a source's state is **rendered** on the page — without
  /// changing the state itself.
  ///
  /// By default a state prints via `toString()`, so a `List<String>` shows as
  /// the cramped `[todo 48, todo 48, todo 49]`. Register a formatter to render
  /// it however reads best:
  ///
  /// ```dart
  /// // one todo per line
  /// StateInspector.instance.format<List<String>>((s) => s.join('\n'));
  ///
  /// // a custom summary for a whole state class
  /// StateInspector.instance.format<CartState>((s) => '${s.items.length} items · \$${s.total}');
  /// ```
  ///
  /// Keyed by the **state** type `T`, not the source type — so one registration
  /// covers every cubit/bloc/notifier whose state is a `T`. Applies to the
  /// current-state line and the from/to lines in the change history alike.
  ///
  /// Without a registration, [display] already handles the common cases —
  /// `List`/`Map`/`Set` one entry per line, `DateTime` as ISO-8601 — and falls
  /// back to `toString()` for everything else. Register a formatter only when
  /// you want something different for a specific type.
  void format<T extends Object>(String Function(T state) render) {
    _formatters[T.toString()] = (state) => render(state as T);
  }

  static const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

  /// Render [value] the way the page should show it.
  ///
  /// Resolution order (first match wins):
  /// 1. a registered [format] override for the value's exact runtime type;
  /// 2. built-in defaults for the common cases — `DateTime` → ISO-8601,
  ///    `List`/`Map`/`Set`/`Iterable` → one entry per line (pretty JSON when
  ///    encodable, element-wise `toString()` otherwise);
  /// 3. `toString()`.
  ///
  /// Never throws — a bad formatter or an un-encodable collection degrades
  /// gracefully.
  String display(Object? value) {
    if (value == null) return 'null';

    // 1 — an app-registered override for this exact type.
    final custom = _formatters[value.runtimeType.toString()];
    if (custom != null) {
      try {
        return custom(value);
      } catch (e) {
        return '${value.toString()}  «formatter threw: $e»';
      }
    }

    // 2 — built-in defaults for the normal cases.
    if (value is DateTime) return value.toIso8601String();

    if (value is Map) return _prettyCollection(value);
    if (value is Iterable) return _prettyCollection(value.toList());

    // 3 — strings, num, bool, enums, and everything else.
    return value.toString();
  }

  /// A `List`/`Map` as an indented, one-entry-per-line block. Uses JSON when the
  /// collection is JSON-encodable (all primitives); otherwise lays it out by
  /// hand so a list/map of domain objects still reads down the page rather than
  /// across it.
  String _prettyCollection(Object collection) {
    try {
      return _prettyJson.convert(collection);
    } catch (_) {
      // Holds non-primitives — JsonEncoder can't take it. Render each entry with
      // its own toString(), which always works.
      if (collection is Map) {
        if (collection.isEmpty) return '{}';
        return collection.entries.map((e) => '${e.key}: ${e.value}').join('\n');
      }
      final list = collection as List;
      if (list.isEmpty) return '[]';
      return list.map((e) => '$e').join('\n');
    }
  }

  /// Changes kept per source. The interesting ones are always the most recent.
  int maxChangesPerSource = 100;

  /// Closed sources are kept so you can still read what happened before they
  /// went away — but not forever.
  int maxClosedSources = 20;

  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  final Map<int, TrackedSource> _sources = {};
  int _nextChangeId = 0;

  /// Live sources first, then recently closed ones. Oldest-created first within
  /// each group, so the list doesn't reshuffle as you watch it.
  List<TrackedSource> get sources {
    final all = _sources.values.toList()
      ..sort((a, b) {
        if (a.isClosed != b.isClosed) return a.isClosed ? 1 : -1;
        return a.created.compareTo(b.created);
      });
    return List.unmodifiable(all);
  }

  /// The source's non-state fields, read **live** from the instance.
  ///
  /// Empty when nothing is registered for it, or when the instance has been
  /// garbage-collected (see [TrackedSource.ref]).
  Map<String, Object?> liveFieldsOf(TrackedSource tracked) {
    final source = tracked.ref?.target;
    return source == null ? const {} : fieldsFor(source);
  }

  /// Register a source the moment it's created, before its first change.
  ///
  /// Optional — [record] lazily registers anything it hasn't seen — but calling
  /// it means a source that never changes still shows up (on its initial state).
  void recordCreate(int id, {required String type, Object? state, Object? instance}) {
    if (!DebugOverlayKillSwitch.enabled) return;

    _sources[id] = TrackedSource(
      id: id,
      type: type,
      created: DateTime.now(),
      state: state,
      ref: instance == null ? null : WeakReference(instance),
    );
    tick.value++;
  }

  /// Record a state change. This is the core of the push API: any adapter calls
  /// it with a stable [id] per instance.
  ///
  /// A source not seen before is registered lazily here rather than dropped, so
  /// sources created before an observer was installed are still tracked.
  void record(
    int id, {
    required String type,
    Object? from,
    Object? to,
    Object? event,
    Object? instance,
  }) {
    if (!DebugOverlayKillSwitch.enabled) return;

    final tracked = _sources.putIfAbsent(
      id,
      () => TrackedSource(
        id: id,
        type: type,
        created: DateTime.now(),
        state: from,
        ref: instance == null ? null : WeakReference(instance),
      ),
    );

    tracked.state = to;
    tracked.changes.insert(
      0,
      StateChangeEntry(id: _nextChangeId++, time: DateTime.now(), from: from, to: to, event: event),
    );

    while (tracked.changes.length > maxChangesPerSource) {
      tracked.changes.removeLast();
    }
    tick.value++;
  }

  /// Attach an error to an already-tracked source.
  void recordError(int id, Object error, StackTrace stackTrace) {
    if (!DebugOverlayKillSwitch.enabled) return;

    final tracked = _sources[id];
    if (tracked == null) return;

    tracked
      ..error = error
      ..stackTrace = stackTrace;
    tick.value++;
  }

  /// Mark a source closed. It's kept (past-tense) so you can see what it did
  /// just before the screen that owned it was popped, then evicted in order.
  void recordClose(int id) {
    if (!DebugOverlayKillSwitch.enabled) return;

    final tracked = _sources[id];
    if (tracked == null) return;

    tracked.closed = DateTime.now();
    _evictOldClosed();
    tick.value++;
  }

  void _evictOldClosed() {
    final closed = _sources.values.where((b) => b.isClosed).toList()..sort((a, b) => a.closed!.compareTo(b.closed!));

    for (var i = 0; i < closed.length - maxClosedSources; i++) {
      _sources.remove(closed[i].id);
    }
  }

  void clear() {
    _sources.clear();
    tick.value++;
  }

  /// Drops every [inspect] and [format] registration. Mostly for tests — the
  /// inspector is a singleton, so a registration would otherwise leak into the
  /// next one.
  @visibleForTesting
  void clearInspectors() {
    _inspectors.clear();
    _formatters.clear();
  }

  /// Drops the closed ones, keeping what's live.
  void clearClosed() {
    _sources.removeWhere((_, b) => b.isClosed);
    tick.value++;
  }
}
