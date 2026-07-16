/// bloc support for `devtray`.
///
/// Install the observer once, and every bloc and cubit shows up on the State
/// page with its change history:
///
/// ```dart
/// Bloc.observer = DebugBlocObserver();
/// ```
///
/// Already have an observer? Chain it — yours keeps working:
///
/// ```dart
/// Bloc.observer = DebugBlocObserver(next: MyObserver());
/// ```
///
/// This is the **only** bloc-specific code in the whole set. `StateInspector`
/// (in the core) is library-agnostic — which is why the State page itself stays
/// in the core, and why a Riverpod app can feed the same page by pushing into
/// the inspector directly. See `state_bridge.dart` there.
library;

export 'src/bloc_adapter.dart';
