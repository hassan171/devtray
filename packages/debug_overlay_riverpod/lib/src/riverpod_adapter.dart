import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Feeds [StateInspector] from Riverpod. Install it on the scope:
///
/// ```dart
/// ProviderScope(
///   observers: [DebugRiverpodObserver()],
///   child: const MyApp(),
/// )
/// ```
///
/// Chains to your own observer if you have one, so existing logging keeps
/// working:
///
/// ```dart
/// ProviderScope(observers: [DebugRiverpodObserver(next: MyObserver())], ...)
/// ```
///
/// This is the **only** file in the package that imports Riverpod. The store it
/// feeds ([StateInspector]) is library-agnostic — which is why the State page
/// itself lives in the core, and why bloc and Riverpod can fill the same page
/// with neither knowing about the other.
///
/// `base`, because Riverpod declares `ProviderObserver` as `abstract base` —
/// it wants the contract implemented by extension only, never `implements`. So
/// the restriction propagates here rather than being a choice.
base class DebugRiverpodObserver extends ProviderObserver {
  final ProviderObserver? next;

  const DebugRiverpodObserver({this.next});

  /// A stable id for the provider, for the lifetime of this app run.
  ///
  /// Keyed on the **provider** rather than its element or value: the same
  /// provider read from two scopes is still the same declaration, and that's
  /// what you're looking for on the page. `identityHashCode` because providers
  /// are const-constructed singletons — the identity *is* the declaration.
  int _idOf(ProviderObserverContext context) => identityHashCode(context.provider);

  /// What the page labels the source.
  ///
  /// A provider's `name` is set when you pass one to the constructor
  /// (`StateProvider(..., name: 'counter')`) or by the code generator. Unnamed
  /// providers fall back to the runtime type — noisier, but never blank.
  String _typeOf(ProviderObserverContext context) => context.provider.name ?? context.provider.runtimeType.toString();

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    StateInspector.instance.recordCreate(
      _idOf(context),
      type: _typeOf(context),
      state: value,
      // No `instance:` — the useful object for a provider is its *value*, which
      // is already the state. Passing the provider itself would let
      // StateInspector.inspect<T> read fields off a const declaration that holds
      // none of the interesting data.
    );
    next?.didAddProvider(context, value);
  }

  @override
  void didUpdateProvider(ProviderObserverContext context, Object? previousValue, Object? newValue) {
    StateInspector.instance.record(
      _idOf(context),
      type: _typeOf(context),
      from: previousValue,
      to: newValue,
      // Riverpod 3 attributes a change to the mutation that caused it, when
      // there is one — the closest thing it has to bloc's event, and worth
      // showing for exactly the same reason.
      event: context.mutation?.toString(),
    );
    next?.didUpdateProvider(context, previousValue, newValue);
  }

  @override
  void providerDidFail(ProviderObserverContext context, Object error, StackTrace stackTrace) {
    StateInspector.instance.recordError(_idOf(context), error, stackTrace);
    next?.providerDidFail(context, error, stackTrace);
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    // `didDisposeProvider`, not `didUnmountProvider`: this fires when the
    // provider's onDispose listeners run, which is when it stops being live —
    // the moment worth showing. Unmounting is a later memory-management detail.
    StateInspector.instance.recordClose(_idOf(context));
    next?.didDisposeProvider(context);
  }
}
