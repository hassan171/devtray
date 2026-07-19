/// Names for the callback shapes that appear across the public API.
///
/// Only the ones that name a *concept* — something the docs already talk about
/// by name, where the raw signature tells you nothing about intent. A typedef
/// that merely abbreviates `Future<void> Function()` into `AsyncCallback` is a
/// worse trade: it hides the shape you need in order to write the call, and
/// groups unrelated things under a label that says only what they return.
library;

import 'devtray_facade.dart';

/// Computes fields to attach to every log entry, fresh each time.
///
/// ```dart
/// devtray.enrich('nav', () => {'screen': router.currentRoute});
/// ```
///
/// Runs on **every** log line, so keep it cheap — a field read, not a platform
/// channel call or a database query. If it throws, the failure is recorded as
/// the field's value and the log line still lands; after repeated failures the
/// enricher is dropped, because one that throws every time would otherwise
/// write its error onto every line in the session.
typedef DevtrayEnricher = Map<String, Object?> Function();

/// Reads the fields worth showing off a live state source — a sync queue, a
/// retry counter, a cache.
///
/// ```dart
/// devtray.inspect<CartCubit>((c) => {'items': c.items.length});
/// ```
///
/// The inspector only ever sees a source's current *state*, and Flutter has no
/// runtime reflection to go find the rest, so this is how you point at it.
/// Registered once per type, read fresh on every rebuild.
typedef DevtrayInspector<T> = Map<String, Object?> Function(T source);

/// Renders a state value for the State page.
///
/// Used by `formatState<T>` (every source whose state is a `T`) and
/// `formatSource<S>` (one source's state, whatever its type — so the argument
/// there is `Object?`).
typedef DevtrayFormatter<T> = String Function(T state);

/// Configures the overlay's stores, inside `runDebugApp(configure:)`.
///
/// ```dart
/// configure: (devtray) => devtray
///   ..excludeUrls(['/health'])
///   ..detectFreezes(),
/// ```
typedef DevtrayConfigure = void Function(Devtray devtray);
