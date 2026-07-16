/// Feeding [StateInspector] from a state-management library other than bloc.
///
/// The State page reads from [StateInspector] and nothing else. Bloc has a
/// bundled adapter ([DebugBlocObserver]); everything else pushes in through the
/// same small API. None of the snippets below live in the package — copying
/// them keeps the package from depending on riverpod, getx, etc. for everyone.
///
/// The API you call:
///
/// - `record(id, type: ..., from: ..., to: ..., event: ..., instance: ...)`
///   for each change. `id` must be **stable per instance** (use
///   `identityHashCode(source)`). `instance` is optional — pass it to enable
///   live non-state field reads via [StateInspector.inspect].
/// - `recordCreate(...)` / `recordError(...)` / `recordClose(...)` for the rest
///   of the lifecycle. All optional — `record` lazily registers anything new.
///
/// ## Riverpod
///
/// Riverpod has a `ProviderObserver` — the same shape as bloc's:
///
/// ```dart
/// class DebugRiverpodObserver extends ProviderObserver {
///   @override
///   void didUpdateProvider(provider, prev, next, container) {
///     StateInspector.instance.record(
///       identityHashCode(provider),
///       type: provider.name ?? provider.runtimeType.toString(),
///       from: prev,
///       to: next,
///     );
///   }
///
///   @override
///   void didDisposeProvider(provider, container) =>
///       StateInspector.instance.recordClose(identityHashCode(provider));
/// }
///
/// // ProviderScope(observers: [DebugRiverpodObserver()], child: ...)
/// ```
///
/// ## ValueNotifier / ChangeNotifier
///
/// No observer exists, so wrap the notifier — or just add a listener:
///
/// ```dart
/// void inspectNotifier<T>(ValueNotifier<T> n, {required String name}) {
///   var last = n.value;
///   StateInspector.instance.recordCreate(identityHashCode(n), type: name, state: last, instance: n);
///   n.addListener(() {
///     StateInspector.instance.record(identityHashCode(n), type: name, from: last, to: n.value, instance: n);
///     last = n.value;
///   });
/// }
/// ```
///
/// ## Plain setState / anything else
///
/// There's nothing to observe, so record the transition yourself where the
/// change happens:
///
/// ```dart
/// void setCount(int next) {
///   StateInspector.instance.record(1, type: 'HomeScreen.count', from: _count, to: next);
///   setState(() => _count = next);
/// }
/// ```
///
/// ## GetX
///
/// A `GetxController`'s reactive fields (`.obs`) expose `listen`:
///
/// ```dart
/// count.listen((v) => StateInspector.instance.record(
///       identityHashCode(controller), type: 'CountController.count', to: v));
/// ```
library;
