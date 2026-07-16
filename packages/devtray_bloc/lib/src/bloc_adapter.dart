import 'package:devtray/devtray.dart';
import 'package:bloc/bloc.dart';


/// Feeds [StateInspector] from `package:bloc`. Install it once:
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
///
/// This is the **only** file in the package that imports `package:bloc`. The
/// store itself ([StateInspector]) is library-agnostic — a non-bloc app never
/// touches this file, and it tree-shakes out of that app's release build. To
/// hook a different state library, push into [StateInspector] directly (see
/// `state_bridge.dart`) instead of using this.
class DebugBlocObserver extends BlocObserver {
  final BlocObserver? next;

  DebugBlocObserver({this.next});

  /// The event from `onTransition`, waiting for the `onChange` it belongs to.
  ///
  /// A Bloc calls `onTransition` **then** `emit` (which fires `onChange`) — see
  /// `Bloc._on`'s `onEmit`. So the event arrives *before* the change it caused,
  /// and has to be held for it. Getting this backwards would staple each event
  /// onto the previous transition. Cubits have no events, so this stays empty
  /// for them.
  ///
  /// Keyed by bloc identity, because two blocs can be mid-transition at once.
  final Map<int, Object?> _pendingEvents = {};

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    StateInspector.instance.recordCreate(
      identityHashCode(bloc),
      type: bloc.runtimeType.toString(),
      state: bloc.state,
      instance: bloc,
    );
    next?.onCreate(bloc);
    super.onCreate(bloc);
  }

  @override
  void onTransition(Bloc<dynamic, dynamic> bloc, Transition<dynamic, dynamic> transition) {
    // Stash the event for the onChange that immediately follows — recording the
    // change here as well would log every bloc transition twice.
    _pendingEvents[identityHashCode(bloc)] = transition.event;
    next?.onTransition(bloc, transition);
    super.onTransition(bloc, transition);
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    // Present for a Bloc (set by onTransition just now), absent for a plain
    // Cubit — which has no events at all.
    final event = _pendingEvents.remove(identityHashCode(bloc));

    StateInspector.instance.record(
      identityHashCode(bloc),
      type: bloc.runtimeType.toString(),
      from: change.currentState,
      to: change.nextState,
      event: event,
      instance: bloc,
    );
    next?.onChange(bloc, change);
    super.onChange(bloc, change);
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    StateInspector.instance.recordError(identityHashCode(bloc), error, stackTrace);
    next?.onError(bloc, error, stackTrace);
    super.onError(bloc, error, stackTrace);
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    // Don't leak a pending event for a bloc that's going away.
    _pendingEvents.remove(identityHashCode(bloc));
    StateInspector.instance.recordClose(identityHashCode(bloc));
    next?.onClose(bloc);
    super.onClose(bloc);
  }
}
