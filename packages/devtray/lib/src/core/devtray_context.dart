import 'dart:async';
import 'dart:collection';

import 'devtray_typedefs.dart';

/// The ambient facts attached to everything devtray captures.
///
/// Three layers, composing least-specific to most:
///
///  1. **context** — set once, carried until changed. Which build, which
///     flavour, who is signed in.
///  2. **enrichers** — computed per entry, for values that must be *current*
///     rather than whatever they were when you last set them: the active route,
///     connectivity.
///  3. **per-call fields** — passed at the call site, for one entry.
///
/// Shared by [DevtrayLog] and [DevtrayNet] rather than owned by either. It used
/// to live inside the log store, which meant a log line could say which screen
/// it came from and a *request* could not — and "which screen fired this
/// request" is usually the more useful question, since a failing request is
/// what you are normally chasing.
///
/// Costs nothing when unused: with no context, no enrichers and no per-call
/// fields, [resolve] returns a shared const map without allocating.
class DevtrayContext {
  DevtrayContext._();

  /// The one instance. Both stores read it; [Devtray] is the public route in.
  static final DevtrayContext instance = DevtrayContext._();

  // ------------------------------------------------------------------ ambient

  final Map<String, Object?> _context = {};

  /// The ambient values, read-only.
  ///
  /// Mutate through [set] / [setAll] / [remove] / [clear], which keep the
  /// snapshot sharing below correct.
  Map<String, Object?> get values => UnmodifiableMapView(_context);

  /// The current context as an immutable snapshot, rebuilt only when it
  /// changes.
  ///
  /// Entries hold a *reference* to this, so unchanged context costs nothing per
  /// entry — but because it is replaced rather than mutated on every change, an
  /// entry keeps the values that were current when it was captured. Holding the
  /// live map instead would be cheaper still and wrong: every past line would
  /// report the screen you are on now.
  Map<String, Object?>? _snapshot;

  /// Adds or replaces one ambient value.
  void set(String key, Object? value) {
    _context[key] = value;
    _snapshot = null;
  }

  /// Adds or replaces several at once.
  void setAll(Map<String, Object?> values) {
    _context.addAll(values);
    _snapshot = null;
  }

  void remove(String key) {
    _context.remove(key);
    _snapshot = null;
  }

  void clear() {
    _context.clear();
    _snapshot = null;
  }

  /// Runs [body] with extra ambient values, then restores what was there.
  ///
  /// Not safe across concurrent async work — it is one shared map, not Zone
  /// state, so overlapping scopes on the same key interleave. Pass the field
  /// explicitly for per-request isolation.
  Future<T> withValues<T>(Map<String, Object?> values, Future<T> Function() body) async {
    final previous = {for (final key in values.keys) key: _context[key]};
    final absent = values.keys.where((k) => !_context.containsKey(k)).toSet();

    setAll(values);
    try {
      return await body();
    } finally {
      for (final entry in previous.entries) {
        if (absent.contains(entry.key)) {
          _context.remove(entry.key);
        } else {
          _context[entry.key] = entry.value;
        }
      }
      _snapshot = null;
    }
  }

  // ---------------------------------------------------------------- enrichers

  final Map<String, DevtrayEnricher> _enrichers = {};

  /// Enrichers dropped for throwing repeatedly, and what they threw.
  final Map<String, Object> _failed = {};
  Map<String, Object> get failedEnrichers => UnmodifiableMapView(_failed);

  /// How many failures an enricher gets before it is dropped.
  static const int _failureLimit = 2;
  final Map<String, int> _failures = {};

  /// Registers a callback that adds fields to every entry, computed fresh.
  ///
  /// Runs on **every** capture, so keep it cheap — a field read, not a platform
  /// channel call. After [_failureLimit] failures it is dropped, because one
  /// that throws every time would otherwise write its error onto every entry in
  /// the session.
  void addEnricher(String name, DevtrayEnricher compute) {
    _enrichers[name] = compute;
    _failed.remove(name);
    _failures.remove(name);
  }

  void removeEnricher(String name) {
    _enrichers.remove(name);
    _failed.remove(name);
    _failures.remove(name);
  }

  void clearEnrichers() {
    _enrichers.clear();
    _failed.clear();
    _failures.clear();
  }

  /// Re-enables an enricher that was dropped for failing.
  void retryEnricher(String name) {
    _failed.remove(name);
    _failures.remove(name);
  }

  // ----------------------------------------------------------------- resolving

  /// Reports an enricher that had to be dropped.
  ///
  /// Set by [DevtrayLog] so the notice lands as a log line. A plain callback
  /// rather than a direct call, because this class must not depend on the log
  /// store — the dependency runs the other way.
  void Function(String message)? onEnricherDropped;

  /// Merges context, enrichers and per-call fields into one map.
  ///
  /// Least specific first, so each layer overwrites the last.
  Map<String, Object?> resolve(Map<String, Object?>? callFields) {
    final hasCall = callFields != null && callFields.isNotEmpty;
    final hasEnrichers = _enrichers.isNotEmpty;

    if (!hasCall && !hasEnrichers) {
      if (_context.isEmpty) return const {};
      // Shared, not copied — see [_snapshot].
      return _snapshot ??= Map.unmodifiable(_context);
    }

    final merged = <String, Object?>{..._context};

    if (hasEnrichers) {
      for (final name in _enrichers.keys.toList()) {
        if (_failed.containsKey(name)) continue;
        try {
          merged.addAll(_enrichers[name]!());
        } catch (e) {
          _noteFailure(name, e, merged);
        }
      }
    }

    if (hasCall) merged.addAll(callFields);
    return merged;
  }

  /// Records a throwing enricher without losing the entry it was decorating.
  ///
  /// The failure becomes the field's value, so a broken enricher is visible on
  /// the entry it broke rather than silently missing.
  void _noteFailure(String name, Object error, Map<String, Object?> merged) {
    merged['$name!'] = 'enricher failed: $error';

    final failures = (_failures[name] ?? 0) + 1;
    _failures[name] = failures;
    if (failures < _failureLimit) return;

    _failed[name] = error;
    _enrichers.remove(name);

    // Queued, not called inline: this runs *inside* a capture, and logging
    // from here would re-enter the store that is mid-write.
    final report = onEnricherDropped;
    if (report == null) return;
    scheduleMicrotask(
      () => report('Enricher "$name" failed $failures times and was removed: $error'),
    );
  }
}
