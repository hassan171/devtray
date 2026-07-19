import '../logs/devtray_export.dart';
import 'devtray_typedefs.dart';
import '../logs/devtray_log.dart';
import '../network/mocking/devtray_mocks.dart';
import '../network/devtray_net.dart';
import '../state/devtray_state.dart';
import '../timeline/devtray_jank.dart';

/// One place to configure the overlay.
///
/// Setup used to be spread across three mechanisms — arguments to
/// [runDebugApp], mutating singletons, and imperative `start()` calls — so
/// wiring up a real app meant touching half a dozen objects in an order nobody
/// stated. That order is not cosmetic: [DevtrayKillSwitch] is set by
/// [runDebugApp], and anything configured *before* it silently does nothing.
///
/// This is a facade over the same singletons, handed to you at the one moment
/// when everything is ready:
///
/// ```dart
/// runDebugApp(
///   app: const MyApp(),
///   enabled: kDebugMode,
///   configure: (d) => d
///     ..excludeUrls(['/health', '/metrics'])
///     ..context({'build': '1.4.2', 'flavor': 'staging'})
///     ..inspect<CartCubit>((c) => {'items': c.items.length})
///     ..detectFreezes(),
///   pages: [...],
/// );
/// ```
///
/// Nothing here is new capability — every method is a line you could write
/// against the singleton yourself, and the singletons remain the API for call
/// sites (`DevtrayLog.instance.log(...)` is exactly right in application code).
/// What this buys is one place to look, and an ordering guarantee.
///
/// **It does not run when the overlay is disabled.** In a release build the
/// callback is skipped entirely, so anything expensive you do inside it — an
/// enricher that reads the filesystem, a sink that opens a socket — costs
/// nothing rather than relying on each store's own kill-switch check.
class Devtray {
  /// Not constructible outside the package: it is handed to `configure`, and an
  /// instance obtained any other way would let you configure things before the
  /// kill switch is set, which is the hazard this exists to remove.
  Devtray._();

  // ----------------------------------------------------------- call sites
  //
  // Statics, not instance methods: these are for *use* rather than setup, and
  // they are the things an app calls constantly — logging is by far the most
  // common thing anyone does with this package.
  //
  // `Devtray.log(...)` rather than `DevtrayLog.instance.log(...)` because the
  // latter reads like a generic utility that happens to be in scope. Naming the
  // tool at the call site is the whole point: someone reading unfamiliar code
  // should be able to tell where a log line goes.
  //
  // The stores stay public for everything else — reading `DevtrayJank.freezes`,
  // feeding `DevtrayNet` from a custom adapter. This is a shorthand for the
  // common path, not a wall around the rest.

  /// Records a log line, visible on the Logs page.
  ///
  /// ```dart
  /// Devtray.log('User signed in', level: LogLevel.info, tag: 'auth');
  /// ```
  ///
  /// A no-op when the overlay is disabled, so this is safe to leave in code
  /// that ships.
  static void log(
    String message, {
    LogLevel level = LogLevel.debug,
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    DevtrayLog.instance.log(
      message,
      level: level,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );
  }

  /// Records an error, badging the launcher and carrying the full report so the
  /// Logs page can expand it.
  ///
  /// Framework and platform errors arrive here on their own via [captureErrors];
  /// this is for the ones you catch yourself.
  static void report(
    Object error, {
    StackTrace? stackTrace,
    ErrorSource source = ErrorSource.reported,
    String? context,
    String? library,
    Map<String, Object?>? fields,
  }) {
    DevtrayLog.instance.report(
      error,
      stackTrace: stackTrace,
      source: source,
      context: context,
      library: library,
      fields: fields,
    );
  }

  /// Adds or replaces one ambient value carried by every subsequent entry.
  ///
  /// For facts that change *during* a session — who signed in, which screen.
  /// Set the ones known at startup in `configure`'s `context` instead.
  ///
  /// ```dart
  /// Devtray.setContext('userId', user.id);
  /// ```
  static void setContext(String key, Object? value) => DevtrayLog.instance.setContext(key, value);

  /// Runs [body] with extra ambient values, then restores what was there.
  ///
  /// ```dart
  /// await Devtray.withContext({'orderId': id}, () async => submitOrder());
  /// ```
  ///
  /// Not safe across concurrent async work — it is one shared map, not Zone
  /// state, so overlapping scopes on the same key interleave. Pass the field
  /// explicitly for per-request isolation.
  static Future<T> withContext<T>(Map<String, Object?> values, Future<T> Function() body) =>
      DevtrayLog.instance.withContext(values, body);

  // ---------------------------------------------------------------- network

  /// Requests whose URL contains any of these are never recorded.
  ///
  /// For high-frequency background traffic — health polls, crash reporting,
  /// analytics beacons — that would otherwise crowd out the requests you care
  /// about in a 500-entry buffer.
  Devtray excludeUrls(List<String> patterns) {
    DevtrayNet.instance.excludedUrlPatterns.addAll(patterns);
    return this;
  }

  /// How many requests to keep, and how much of each response body.
  ///
  /// Bodies are retained for the life of an entry, so the cap is what stops a
  /// handful of large responses dwarfing the app. Raise it to inspect big
  /// payloads; lower it on a memory-tight device.
  Devtray network({int? maxEntries, int? maxBodyChars, NetworkErrorReporting? errorReporting}) {
    final store = DevtrayNet.instance;
    if (maxEntries != null) store.maxEntries = maxEntries;
    if (maxBodyChars != null) store.maxBodyChars = maxBodyChars;
    if (errorReporting != null) store.errorReporting.value = errorReporting;
    return this;
  }

  /// Turns request mocking off entirely — interception *and* the UI.
  ///
  /// One switch rather than two, because two could disagree: hiding the mocking
  /// UI while rules added from code went on faking traffic is a state with no
  /// way to see it.
  Devtray disableMocking() {
    DevtrayMocks.instance.disable();
    return this;
  }

  /// Where mock rules are persisted across restarts.
  ///
  /// Installing a backend *is* the opt-in — the default is in-memory, so rules
  /// are session-only until you set this. `devtray_prefs` supplies one.
  Devtray persistMockRules(MockRuleStorage storage) {
    DevtrayMocks.instance.storage = storage;
    return this;
  }

  // ------------------------------------------------------------------- logs

  /// How many log lines to keep, and whether to flush pending ones when the app
  /// is backgrounded.
  ///
  /// [flushOnPause] is what makes a batched [FlushPolicy] safe enough to be the
  /// default: backgrounding is the last moment before the OS may kill the
  /// process, so it is the cheapest opportunity not to lose the buffer. Turn it
  /// off only if you have your own lifecycle handling.
  Devtray logs({int? maxEntries, bool? flushOnPause}) {
    if (maxEntries != null) DevtrayLog.instance.maxEntries = maxEntries;
    if (flushOnPause != null) DevtrayExport.instance.flushOnPause = flushOnPause;
    return this;
  }

  /// Values attached to **every** log line and error from here on.
  ///
  /// For facts true of a whole span of the session — which build, which
  /// flavour, who is signed in. The payoff is errors nobody anticipated: a
  /// crash report that says *whose* crash it was, without the throw site
  /// knowing anything about it.
  Devtray context(Map<String, Object?> values) {
    DevtrayLog.instance.setContextAll(values);
    return this;
  }

  /// Registers a callback that adds fields to every entry, computed fresh.
  ///
  /// For values that must be *current* rather than whatever they were when you
  /// last set them — the active route, connectivity. Runs on every log line, so
  /// keep it cheap: this is not the place for a platform channel call.
  Devtray enrich(String name, DevtrayEnricher compute) {
    DevtrayLog.instance.addEnricher(name, compute);
    return this;
  }

  /// Sends captured logs somewhere durable — a file, an upload, your own crash
  /// reporter. `devtray_log_file` supplies a rotating-file sink.
  ///
  /// Nothing is written until a sink is added, and entries reach sinks *before*
  /// the ring buffer evicts, so a long session lands on disk in full even though
  /// the page only ever shows the last [logs] entries.
  Devtray logTo(LogSink sink, {FlushPolicy? policy}) {
    if (policy != null) DevtrayExport.instance.policy = policy;
    DevtrayExport.instance.addSink(sink);
    return this;
  }

  /// Adds a sink that has to be opened asynchronously — the file case, since
  /// creating the directory and pruning old sessions both touch the disk.
  ///
  /// ```dart
  /// ..logToAsync(() => FileLogSink.open())
  /// ```
  ///
  /// [configure] itself stays synchronous on purpose: making it `async` would
  /// mean the app's first frame waited on every registration in it, including
  /// the cheap ones. Instead the future is *started* here and awaited by
  /// [runDebugApp] before it runs your app, so lines logged during bootstrap
  /// still reach the sink.
  ///
  /// A sink that fails to open is reported into the log and skipped, rather
  /// than taking down the launch of an app it exists to observe.
  Devtray logToAsync(Future<LogSink> Function() open, {FlushPolicy? policy}) {
    if (policy != null) DevtrayExport.instance.policy = policy;

    _pending.add(() async {
      try {
        DevtrayExport.instance.addSink(await open());
      } catch (e) {
        DevtrayLog.instance.log(
          'A log sink failed to open and was skipped: $e',
          level: LogLevel.error,
          tag: 'devtray',
        );
      }
    });
    return this;
  }

  /// Work started during [configure] that [runDebugApp] awaits before running
  /// the app.
  final List<Future<void> Function()> _pending = [];

  // ------------------------------------------------------------------ state

  /// Shows fields a source holds **outside** its state — a sync queue, a retry
  /// counter, a cache.
  ///
  /// The inspector only ever sees the current state value and Flutter has no
  /// runtime reflection, so you point at the rest. Registered once, applies to
  /// every instance of that type, read fresh on every rebuild.
  Devtray inspect<T extends Object>(DevtrayInspector<T> extract) {
    DevtrayState.instance.inspect<T>(extract);
    return this;
  }

  /// Registers several [inspect] extractors in one call.
  ///
  /// ```dart
  /// ..inspectAll([
  ///   Inspect<CartCubit>((c) => {'items': c.items.length}),
  ///   Inspect<Session>((s) => {'signIns': s.signIns}),
  /// ])
  /// ```
  ///
  /// Each entry carries its own type, which is why they are [Inspect] objects
  /// rather than plain closures: `inspect<T>` is keyed by type, and a list of
  /// bare functions would erase the very thing the registry is indexed on.
  ///
  /// Equivalent to repeating `..inspect<T>(...)`, which remains perfectly good
  /// — reach for this when a list reads better than a cascade, not because the
  /// cascade is wrong.
  Devtray inspectAll(List<Inspect<Object>> inspectors) {
    for (final i in inspectors) {
      i._register();
    }
    return this;
  }

  /// Controls how a state *type* is rendered on the State page.
  Devtray formatState<T extends Object>(DevtrayFormatter<T> render) {
    DevtrayState.instance.format<T>(render);
    return this;
  }

  /// Controls how one *source's* state is rendered — scoped to that cubit or
  /// notifier rather than every value of the same type.
  Devtray formatSource<S extends Object>(DevtrayFormatter<Object?> render) {
    DevtrayState.instance.formatSource<S>(render);
    return this;
  }

  /// How much state history to keep, and whether to hold the real objects.
  ///
  /// `retainStateObjects` is off by design: history holds up to
  /// [maxChangesPerSource] values per source, and keeping large state objects
  /// strongly would make this debug tool the thing pinning them in memory —
  /// the exact leak it exists to help you find. Turn it on only when you need
  /// the real objects back, and expect the cost.
  Devtray state({int? maxChangesPerSource, int? maxClosedSources, bool? retainStateObjects}) {
    final inspector = DevtrayState.instance;
    if (maxChangesPerSource != null) inspector.maxChangesPerSource = maxChangesPerSource;
    if (maxClosedSources != null) inspector.maxClosedSources = maxClosedSources;
    if (retainStateObjects != null) inspector.retainStateObjects = retainStateObjects;
    return this;
  }

  // ------------------------------------------------------------------- jank

  /// Watches for UI freezes and slow frames for the whole session.
  ///
  /// The only capture in the overlay with a real steady-state cost — a
  /// heartbeat timer plus a per-frame callback — which is why it is opt-in.
  ///
  /// Starting it here rather than via `TimelineDebugPage(detectFreezes: true)`
  /// means a freeze is recorded even while the overlay is closed, or while you
  /// are on another tab. The page-scoped flag only watches while that page is
  /// mounted.
  ///
  /// Detection is retrospective and cannot be otherwise: a blocked isolate runs
  /// no timer, so a freeze is only reported once it ends and a terminal hang is
  /// reported by nothing. See [DevtrayJank].
  Devtray detectFreezes({
    Duration? threshold,
    Duration? slowFrameThreshold,
    Duration? heartbeatInterval,
    int? maxFreezes,
    int? maxSlowFrames,
  }) {
    final watchdog = DevtrayJank.instance;
    if (threshold != null) watchdog.freezeThreshold = threshold;
    if (slowFrameThreshold != null) watchdog.slowFrameThreshold = slowFrameThreshold;
    if (heartbeatInterval != null) watchdog.heartbeatInterval = heartbeatInterval;
    if (maxFreezes != null) watchdog.maxFreezes = maxFreezes;
    if (maxSlowFrames != null) watchdog.maxSlowFrames = maxSlowFrames;
    watchdog.start();
    return this;
  }

  // ------------------------------------------------------------------ hatch

  /// Anything this facade does not cover.
  ///
  /// A deliberate escape hatch, so a missing convenience method is never a
  /// reason to configure something *outside* the callback and lose the ordering
  /// guarantee. Reach straight for the singletons:
  ///
  /// ```dart
  /// ..raw(() => DevtrayNet.instance.errorReporting.value = ...)
  /// ```
  Devtray raw(void Function() configure) {
    configure();
    return this;
  }
}

/// One typed entry for [Devtray.inspectAll].
///
/// ```dart
/// Inspect<CartCubit>((c) => {'items': c.items.length, 'total': c.total})
/// ```
///
/// Exists because `inspect<T>` is keyed by the source *type*, and a list of
/// plain callbacks would erase it — `List<Map Function(Object)>` cannot say
/// which entry is for which class. Wrapping each one preserves `T` all the way
/// to registration, so the callback still receives a `CartCubit` rather than an
/// `Object` you have to cast.
class Inspect<T extends Object> {
  /// Reads the fields worth showing off a live source.
  final DevtrayInspector<T> extract;

  const Inspect(this.extract);

  /// Registers with the inspector, with `T` intact.
  ///
  /// Private because it is meaningful only inside `configure` — registering
  /// before the kill switch is set is the hazard the facade exists to remove.
  void _register() => DevtrayState.instance.inspect<T>(extract);
}

/// Builds a [Devtray], runs [configure] against it, and completes any
/// asynchronous registrations it started.
///
/// Package-internal: [runDebugApp] calls this at the one point where the kill
/// switch is set and the binding exists.
Future<void> applyDevtraySetup(DevtrayConfigure configure) async {
  final setup = Devtray._();
  configure(setup);

  // Awaited before the app runs, so a line logged during bootstrap reaches a
  // file sink rather than falling in the gap between "configured" and "open".
  for (final pending in setup._pending) {
    await pending();
  }
}
