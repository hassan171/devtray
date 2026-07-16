/// Riverpod support for `debug_overlay`.
///
/// Install the observer on your scope, and every provider shows up on the State
/// page with its change history:
///
/// ```dart
/// ProviderScope(
///   observers: [DebugRiverpodObserver()],
///   child: const MyApp(),
/// )
/// ```
///
/// Already have an observer? Chain it — yours keeps working:
///
/// ```dart
/// ProviderScope(observers: [DebugRiverpodObserver(next: MyObserver())], ...)
/// ```
///
/// Name your providers to get readable rows — `StateProvider(..., name: 'cart')`
/// — otherwise the page falls back to the runtime type.
///
/// The State page itself lives in the core and knows nothing about Riverpod: it
/// reads from `StateInspector`, which is library-agnostic. This package is the
/// ~50 lines of glue between the two, and `debug_overlay_bloc` is the same
/// glue for bloc. Both can be installed at once; the page shows both.
library;

export 'src/riverpod_adapter.dart';
