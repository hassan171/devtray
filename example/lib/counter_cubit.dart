import 'package:bloc/bloc.dart';
import 'package:debug_overlay/debug_overlay.dart';

/// A plain cubit — no events, just emits.
///
/// Note `history` and `lastTouched`: they're **not in the state**, they're just
/// fields. `BlocObserver` never sees them, and Flutter has no reflection to go
/// find them — so the State page can only show them if something points at them.
///
/// This cubit is wired up from the OUTSIDE, in main.dart:
///
/// ```dart
/// StateInspector.instance.inspect<CounterCubit>((c) => {
///   'history': c.history,
///   'lastTouched': c.lastTouched,
/// });
/// ```
///
/// …which keeps the debug import out of the class entirely. Compare [TodoBloc],
/// which does the same thing from the inside.
class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  /// Not in the state — a plain field, invisible to the observer.
  final List<int> history = [];

  DateTime? lastTouched;

  void increment() {
    history.add(state + 1);
    lastTouched = DateTime.now();
    emit(state + 1);
  }

  void decrement() {
    history.add(state - 1);
    lastTouched = DateTime.now();
    emit(state - 1);
  }

  /// Touches a field WITHOUT emitting — the case that proves the point. The page
  /// only rebuilds on emits, so this only shows up when you hit "Re-read fields".
  void touch() => lastTouched = DateTime.now();

  void reset() => emit(0);

  /// Lands in the source's Error section on the State page.
  void boom() => addError(StateError('Something broke in CounterCubit'), StackTrace.current);
}

/// A real Bloc — so the State page can show the **event** that caused each
/// change, which a plain cubit doesn't have.
sealed class TodoEvent {
  const TodoEvent();
}

class TodoAdded extends TodoEvent {
  final String title;
  const TodoAdded(this.title);

  @override
  String toString() => 'TodoAdded("$title")';
}

class TodoCleared extends TodoEvent {
  const TodoCleared();

  @override
  String toString() => 'TodoCleared';
}

/// The other way to expose non-state fields: implement [DebugInspectable].
///
/// Lives next to the fields it exposes, so it can't drift out of sync — at the
/// cost of a debug_overlay import in the class. (A [StateInspector.inspect]
/// registration would override this, so you can still change what's shown from
/// the outside.)
class TodoBloc extends Bloc<TodoEvent, List<String>> implements DebugInspectable {
  TodoBloc() : super(const []) {
    on<TodoAdded>((event, emit) {
      addedCount++;
      emit([...state, event.title]);
    });
    on<TodoCleared>((event, emit) {
      clearedCount++;
      emit(const []);
    });
  }

  // Not in the state — just counters on the bloc.
  int addedCount = 0;
  int clearedCount = 0;

  @override
  Map<String, Object?> get debugFields => {
    'addedCount': addedCount,
    'clearedCount': clearedCount,
    // Keep values small — `length` reads better than dumping a 500-item list.
    'items': state.length,
  };
}
