import 'package:devtray/devtray.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Feeds [DevtrayState] from Riverpod. Install it on the scope:
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
/// feeds ([DevtrayState]) is library-agnostic — which is why the State page
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
  /// (`NotifierProvider(..., name: 'counter')`) or by the code generator.
  /// Unnamed providers fall back to the runtime type — noisier, but never blank.
  String _typeOf(ProviderObserverContext context) => context.provider.name ?? context.provider.runtimeType.toString();

  /// The live Notifier behind the provider, or null for a plain `Provider`.
  ///
  /// This is what [DevtrayState.inspect] needs: the object whose fields it
  /// reads. A bloc IS that object, so `DebugBlocObserver` just passes the bloc.
  /// Riverpod splits the two — the *provider* is a const declaration holding
  /// nothing, and the *notifier* is where a `signIns` counter or a cache would
  /// live. So `inspect<Session>` wants the Session, not the provider.
  ///
  /// The observer context only exposes the provider (its element is private), so
  /// the notifier is read back out of the container. That's safe here: the
  /// provider is already initialised by the time an observer fires, so this
  /// can't trigger a build or recurse.
  ///
  /// Null for a `Provider`/`FutureProvider` — those have no notifier, and their
  /// value is already the state. Nothing to inspect beyond it.
  Object? _notifierOf(ProviderObserverContext context) {
    // `.notifier` lives on Riverpod's internal $ClassProvider, which isn't
    // exported — so there's no public type to test against, and this asks
    // dynamically instead. A provider without one (a plain Provider, a
    // FutureProvider) throws NoSuchMethodError and gets null, which is correct:
    // its value already IS the state, and there are no other fields to read.
    try {
      // Dynamic all the way down: `.notifier` returns a Refreshable, which isn't
      // exported either, so there's nothing to cast to.
      final dynamic container = context.container;
      return container.read((context.provider as dynamic).notifier) as Object?;
    } catch (_) {
      // Also covers a provider mid-failure, whose notifier can't be read. Not
      // worth taking the observer down for — the state and the error are
      // recorded either way.
      return null;
    }
  }

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    // Checked here, not just inside DevtrayState: _notifierOf() below does a
    // dynamic read that throws NoSuchMethodError for every plain Provider and
    // FutureProvider, and constructing a thrown exception (with its stack) on
    // every provider event is not something a release build should pay for.
    // The observer stays installed for the process lifetime, so without this
    // an app that ships it keeps paying.
    if (Devtray.enabled) {
      DevtrayState.instance.recordCreate(
        _idOf(context),
        type: _typeOf(context),
        state: value,
        instance: _notifierOf(context),
      );
    }
    next?.didAddProvider(context, value);
  }

  @override
  void didUpdateProvider(ProviderObserverContext context, Object? previousValue, Object? newValue) {
    if (Devtray.enabled) {
      DevtrayState.instance.record(
        _idOf(context),
        type: _typeOf(context),
        from: previousValue,
        to: newValue,
        instance: _notifierOf(context),
        // Riverpod 3 attributes a change to the mutation that caused it, when
        // there is one — the closest thing it has to bloc's event, and worth
        // showing for exactly the same reason.
        event: context.mutation?.toString(),
      );
    }
    next?.didUpdateProvider(context, previousValue, newValue);
  }

  @override
  void providerDidFail(ProviderObserverContext context, Object error, StackTrace stackTrace) {
    DevtrayState.instance.recordError(_idOf(context), error, stackTrace);
    next?.providerDidFail(context, error, stackTrace);
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    // `didDisposeProvider`, not `didUnmountProvider`: this fires when the
    // provider's onDispose listeners run, which is when it stops being live —
    // the moment worth showing. Unmounting is a later memory-management detail.
    DevtrayState.instance.recordClose(_idOf(context));
    next?.didDisposeProvider(context);
  }
}
