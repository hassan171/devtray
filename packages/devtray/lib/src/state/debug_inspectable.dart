/// A state source (cubit/bloc/notifier/…) that exposes fields the State page
/// should show **alongside its state**.
///
/// ## Why this is needed
///
/// The inspector only ever sees a source's current state value. Anything else a
/// cubit holds — a sync queue, a lookup map, a retry counter — is just an
/// instance field on a class the package has never heard of, and Flutter has no
/// runtime reflection to go find it. So the source has to say what to show.
///
/// ```dart
/// class SyncCubit extends Cubit<SyncState> implements DebugInspectable {
///   final queue = <SyncItem>[];
///   int retries = 0;
///
///   @override
///   Map<String, Object?> get debugFields => {
///         'queue': queue.length,
///         'next': queue.firstOrNull,
///         'retries': retries,
///       };
/// }
/// ```
///
/// **Prefer [DevtrayState.inspect] if you'd rather not import this package
/// from your production classes** — it does the same thing from the outside, and
/// it wins over this interface when both are present.
///
/// Read fresh every time the page rebuilds, so the values are live.
abstract class DebugInspectable {
  /// Whatever is worth seeing. Values are rendered with `toString()`, so keep
  /// them small — `queue.length` reads better than a 500-item list.
  Map<String, Object?> get debugFields;
}
