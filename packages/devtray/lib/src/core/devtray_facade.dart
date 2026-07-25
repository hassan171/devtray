import 'package:flutter/foundation.dart';

import '../logs/devtray_export.dart';
import 'devtray_listeners.dart';
import 'devtray_typedefs.dart';
import '../logs/devtray_log.dart';
import '../network/mocking/devtray_mocks.dart';
import '../nav/devtray_nav.dart';
import '../nav/devtray_nav_observer.dart';
import '../network/devtray_net.dart';
import '../network/network_export.dart';
import '../state/devtray_state.dart';
import '../timeline/devtray_jank.dart';

/// The one control surface: configure it, switch it off, open the panel.
///
/// These used to be three unrelated objects. `DevtrayKillSwitch.enabled` turned
/// capture on and off, a `DevtrayController` you constructed and injected opened
/// the panel and hid the launcher, and setup was spread across arguments to
/// [runDebugApp] plus a handful of mutating singletons. Three things to learn,
/// and — worse — several of them said the same thing in more than one place, so
/// they could disagree.
///
/// ```dart
/// runDebugApp(
///   () => const MyApp(),
///   configure: (d) => d
///     ..excludeUrls(['/health', '/metrics'])
///     ..context({'build': '1.4.2', 'flavor': 'staging'})
///     ..inspect<CartCubit>((c) => {'items': c.items.length})
///     ..detectFreezes(),
///   pages: [...],
/// );
///
/// // …anywhere later:
/// Devtray.log('User signed in');
/// Devtray.open();               // a shake detector, a 5-tap gesture
/// Devtray.enabled = false;      // stop capturing, drop what was captured
/// ```
///
/// ## Three axes, deliberately not merged into one
///
/// It is tempting to read "one control surface" as "one boolean". These answer
/// different questions and an app legitimately wants them in different
/// combinations — capture running in a staging build with no visible affordance
/// is the obvious one:
///
/// | | Question | Here |
/// |---|---|---|
/// | **Capture** | is it recording? | [enabled], [capture] |
/// | **Visibility** | can it be seen or opened? | [open], [showLauncher], [launcher] |
/// | **Existence** | is it in the tree at all? | your own `if` around [runDebugApp] |
///
/// The third is not a switch on purpose. Wrapping the whole package in a plain
/// `if` is clearer than a flag that has to half-work — a flag could only be read
/// *after* the capture Zone and the error hooks were already installed, which is
/// exactly the ordering trap the rest of this class exists to remove.
///
/// ## Configuration, and why it takes an instance
///
/// The chainable methods below ([excludeUrls], [network], [logs], …) are
/// instance methods on an object you never construct — [runDebugApp] hands one
/// to `configure` at the single moment when the binding exists and the capture
/// hooks are installed. Anything configured before that
/// point silently does nothing, and making the object unconstructible is what
/// makes that mistake impossible rather than merely documented.
///
/// Nothing there is new capability — every method is a line you could write
/// against the singleton yourself, and the singletons remain public for
/// everything else. What it buys is one place to look, and an ordering
/// guarantee.
///
/// **`configure` runs regardless of [enabled].** It sets *settings*, and a
/// setting applied while capture is off has to still be there if capture is
/// switched back on mid-session. Each store's own write-time check is what makes
/// a disabled build record nothing.
class Devtray {
  /// Not constructible outside the package: it is handed to `configure`, and an
  /// instance obtained any other way would let you configure things before the
  /// capture hooks exist, which is the hazard this exists to remove.
  Devtray._();

  // -------------------------------------------------------------- capture
  //
  // Was DevtrayKillSwitch, a separate class whose only job was holding one
  // boolean that every store consulted. Folded in here because "is devtray
  // recording" is not a different subject from the rest of this class.

  static bool _enabled = kDebugMode;

  /// Whether anything is captured at all. Defaults to [kDebugMode].
  ///
  /// Every store checks this on write and mocks never intercept, so a release
  /// build records nothing without you remembering anything.
  ///
  /// It has to exist separately from *where you install devtray* because the
  /// adapters are installed by you, not by the overlay:
  ///
  /// ```dart
  /// final dio = Dio()..interceptors.add(DebugDioInterceptor());   // ← always on
  /// ```
  ///
  /// Without this switch that interceptor would go on filling a 500-entry buffer
  /// with requests, headers and auth tokens in a shipped build, with nothing to
  /// read it and no reason to exist.
  ///
  /// Flip it at runtime for a support build where the tools sit behind a login:
  ///
  /// ```dart
  /// Devtray.enabled = user.isInternal;
  /// ```
  ///
  /// Turning it **off** also clears whatever the stores already hold — otherwise
  /// flipping the switch would leave behind the very buffer it exists to
  /// prevent.
  static bool get enabled => _enabled;

  static set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      for (final listener in _disableListeners) {
        listener();
      }
    }
  }

  static final List<VoidCallback> _disableListeners = [];

  /// Called when [enabled] is turned **off**, so a store can drop what it has
  /// already captured.
  ///
  /// The stores register themselves; you shouldn't need this.
  static void addDisableListener(VoidCallback listener) => _disableListeners.add(listener);

  // ------------------------------------------------------------- visibility
  //
  // Was DevtrayController, a ChangeNotifier you constructed and passed to both
  // runDebugApp and DevtrayOverlay. One process has one panel, so holding that
  // state here removes the injection *and* the `showLauncher` duplication that
  // came with it — the widget arg, the runDebugApp arg and the controller field
  // were three ways to say one thing, and the widget's was silently ignored
  // whenever a controller was supplied.

  static final ValueNotifier<bool> _isOpen = ValueNotifier(false);

  /// Whether the floating launcher button is drawn.
  ///
  /// Set it to false for an app with no visible debug affordance at all —
  /// [open] still works, so your own trigger (a shake, five taps on the logo, a
  /// hidden settings row) is the only way in.
  ///
  /// `runDebugApp(showLauncher:)` and `configure: (d) => d..launcher(...)` both
  /// set this. Setting it explicitly — by either route, or by assigning here —
  /// always wins over the widget's default, whenever the overlay happens to
  /// mount. See [seedShowLauncher].
  static bool get showLauncher => _showLauncher.value;

  static set showLauncher(bool value) {
    _showLauncherSetExplicitly = true;
    _showLauncher.value = value;
  }

  static final ValueNotifier<bool> _showLauncher = ValueNotifier(true);
  static bool _showLauncherSetExplicitly = false;

  /// Applies [DevtrayOverlay.showLauncher] without overriding a real choice.
  ///
  /// The widget's argument is a *default*, and it arrives late: the overlay
  /// mounts after `configure` has already run, so seeding unconditionally would
  /// silently undo `..launcher(false)` a frame later. This is what keeps the two
  /// routes from disagreeing — a value set on purpose stands, and the widget's
  /// default only fills in when nobody said otherwise.
  static void seedShowLauncher(bool value) {
    if (_showLauncherSetExplicitly) return;
    _showLauncher.value = value;
  }

  /// Whether the tools panel is currently open.
  static bool get isOpen => _isOpen.value;

  /// Opens the tools panel.
  static void open() => _isOpen.value = true;

  /// Closes the tools panel.
  static void close() => _isOpen.value = false;

  /// Opens the panel if closed, closes it if open.
  static void toggle() => _isOpen.value = !_isOpen.value;

  /// The panel's open state, for the overlay to listen to.
  ///
  /// Exposed rather than private because [DevtrayPresentation.custom] means you
  /// render [DebugToolsScreen] yourself and need the on/off signal.
  static ValueListenable<bool> get isOpenListenable => _isOpen;

  /// The launcher's visibility, for the overlay to listen to.
  static ValueListenable<bool> get showLauncherListenable => _showLauncher;

  /// Restores every switch to its default — the switch and the panel state are
  /// process-global, so a test that touches either would otherwise leak into
  /// every test after it.
  ///
  /// The notifiers are deliberately *not* disposed: they outlive any one widget
  /// tree, and disposing them would leave the next `pumpWidget` listening to a
  /// dead notifier.
  @visibleForTesting
  static void reset() {
    _enabled = kDebugMode;
    _isOpen.value = false;
    _showLauncher.value = true;
    _showLauncherSetExplicitly = false;
    // Registrations are process-global too, so a listener left behind by one
    // test would fire for every test after it.
    clearListeners();
  }

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

  /// How many requests to keep, how much of each response body, and which
  /// headers are hidden from every output.
  ///
  /// Bodies are retained for the life of an entry, so the cap is what stops a
  /// handful of large responses dwarfing the app. Raise it to inspect big
  /// payloads; lower it on a memory-tight device.
  ///
  /// ```dart
  /// ..network(hideHeaders: {'authorization', 'cookie', 'x-api-key'})
  /// ```
  ///
  /// [hideHeaders] **redacts**: everywhere a hidden header would leave the
  /// device — the detail pane, copy-as-cURL, [DebugReport], any [NetworkSink] —
  /// its value is replaced with `••••••` while the name is kept. So a reader
  /// sees an `authorization` header *was* sent without seeing the token, and
  /// the request keeps its shape. This is for secrets, not clutter: a masked
  /// `user-agent` still shows a `user-agent: ••••••` line.
  ///
  /// Set [headerHiding] to [HeaderHiding.omit] to drop hidden headers entirely
  /// rather than mask them — for decluttering, or when even a header's presence
  /// is more than a screenshot should reveal.
  ///
  /// This governs what *leaves* the entry: the value is still on the live entry
  /// in memory. To keep a header out of memory, strip it in your adapter before
  /// it reaches [DevtrayNet.add].
  ///
  /// Names are matched case-insensitively: HTTP header names are
  /// case-insensitive and a Dart `Set` is not, so `Authorization` and
  /// `authorization` must not be two different answers. Both the set and
  /// [hideHeader] apply, so a set literal can cover the common names while a
  /// predicate catches a family:
  ///
  /// ```dart
  /// ..network(hideHeader: (name) => name.startsWith('x-internal-'))
  /// ```
  ///
  /// Each call *adds* to the hidden names rather than replacing them, matching
  /// [excludeUrls] — two calls in one `configure` should accumulate, not have
  /// the last quietly win. Reach for [DevtrayNet.hiddenHeaderNames] directly to
  /// clear or replace the set.
  ///
  /// [hideAllHeaders] hides every header at once, no list to maintain, and wins
  /// over both other filters:
  ///
  /// ```dart
  /// ..network(hideAllHeaders: true, headerHiding: HeaderHiding.omit)
  /// ```
  Devtray network({
    int? maxEntries,
    int? maxBodyChars,
    NetworkErrorReporting? errorReporting,
    Set<String>? hideHeaders,
    bool Function(String name)? hideHeader,
    bool? hideAllHeaders,
    HeaderHiding? headerHiding,
  }) {
    final store = DevtrayNet.instance;
    if (maxEntries != null) store.maxEntries = maxEntries;
    if (maxBodyChars != null) store.maxBodyChars = maxBodyChars;
    if (errorReporting != null) store.errorReporting.value = errorReporting;
    // Lowercased here, once, rather than on every render: the pane consults
    // this per header per rebuild, and the set is written a handful of times at
    // startup.
    if (hideHeaders != null) store.hiddenHeaderNames.addAll(hideHeaders.map((h) => h.toLowerCase()));
    if (hideHeader != null) store.hiddenHeaderPredicate = hideHeader;
    if (hideAllHeaders != null) store.hideAllHeaders = hideAllHeaders;
    if (headerHiding != null) store.headerHiding = headerHiding;
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
  /// last set them — the active route, connectivity.
  ///
  /// Runs for **log lines and network requests alike**, so one registration
  /// answers "which screen was I on" for both:
  ///
  /// ```dart
  /// ..enrich('nav', () => {'screen': router.currentRoute})
  /// ```
  ///
  /// Runs on every capture, so keep it cheap: this is not the place for a
  /// platform channel call.
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

  /// Sends captured **requests** somewhere durable — a file, an upload.
  ///
  /// The network counterpart to [logTo]. Requests are written when they
  /// *complete*, since the status, body and duration all arrive with the
  /// response; anything still in flight is written when the app is
  /// backgrounded, so a process killed mid-request still leaves a record.
  ///
  /// ```dart
  /// ..networkTo(FileNetworkSink(...))
  /// ```
  Devtray networkTo(NetworkSink sink, {FlushPolicy? policy}) {
    if (policy != null) DevtrayNetExport.instance.policy = policy;
    DevtrayNetExport.instance.addSink(sink);
    return this;
  }

  /// Adds a request sink that has to be opened asynchronously — the file case.
  ///
  /// Awaited by [runDebugApp] before your app runs, so requests made during
  /// bootstrap still reach it.
  Devtray networkToAsync(Future<NetworkSink> Function() open, {FlushPolicy? policy}) {
    if (policy != null) DevtrayNetExport.instance.policy = policy;

    _pending.add(() async {
      try {
        DevtrayNetExport.instance.addSink(await open());
      } catch (e) {
        DevtrayLog.instance.log(
          'A network sink failed to open and was skipped: $e',
          level: LogLevel.error,
          tag: 'devtray',
        );
      }
    });
    return this;
  }

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

  // ----------------------------------------------------- capture, visibility

  /// Whether anything is captured at all, from `configure`.
  ///
  /// ```dart
  /// configure: (d) => d
  ///   ..capture(true)          // record in release too
  ///   ..launcher(kDebugMode),  // but no visible affordance
  /// ```
  ///
  /// The same switch as [Devtray.enabled], which defaults to [kDebugMode]. Here
  /// for the same reason [launcher] is: an app that decides this at startup can
  /// say so alongside everything else it configures, rather than in a separate
  /// statement before the call. Assign the static directly to change it later in
  /// the session.
  ///
  /// The case for turning it **on** is a build that ships the tray on purpose —
  /// QA pulling network logs off a TestFlight build, with the launcher gated to
  /// a few accounts. Capture and visibility are separate switches precisely so
  /// that combination is expressible: recording runs for everyone, so the tray
  /// holds a full session the moment it is opened, rather than starting empty
  /// from the point someone signed in.
  ///
  /// Turning it **off** also drops whatever the stores already hold — see
  /// [Devtray.enabled].
  Devtray capture(bool enabled) {
    Devtray.enabled = enabled;
    return this;
  }

  /// Whether the floating launcher button is drawn, from `configure`.
  ///
  /// ```dart
  /// configure: (d) => d..launcher(false),
  /// ```
  ///
  /// The same switch as [Devtray.showLauncher] — here so an app that decides
  /// this at startup can say so alongside everything else it configures, rather
  /// than in a separate statement. Assign the static directly to change it later
  /// in the session.
  ///
  /// With it off there is no visible affordance at all: [Devtray.open] from your
  /// own trigger (a shake, five taps on the logo, a hidden settings row) is the
  /// only way in.
  ///
  /// Note this is applied when `configure` runs — `runDebugApp(showLauncher:)`
  /// seeds the same value, so passing both means this one wins.
  Devtray launcher(bool visible) {
    Devtray.showLauncher = visible;
    return this;
  }

  /// Opens the tools panel as soon as the app starts.
  ///
  /// For iterating on a page inside the overlay itself — hot restart lands you
  /// back on it rather than making you tap in every time.
  Devtray openOnStart() {
    Devtray.open();
    return this;
  }

  // -------------------------------------------------------------------- nav

  /// Records which screen the app is on, from your own navigation.
  ///
  /// ```dart
  /// onDestinationSelected: (i) {
  ///   Devtray.screen(_titles[i]);
  ///   setState(() => _tab = i);
  /// }
  /// ```
  ///
  /// For an app whose navigation is the Navigator, install
  /// [DevtrayNavObserver] instead and this happens with no call sites at all.
  /// This is for the case an observer cannot see — an `IndexedStack` or a
  /// `PageView` whose body swaps without pushing a route. Both feed the same
  /// history, so an app doing both gets one coherent picture.
  static void screen(String name) => DevtrayNav.instance.enter(name);

  /// How much route history to keep, and whether each change is also logged.
  ///
  /// [logNavigation] is off by default: the `screen` field already puts the
  /// route on every entry, so the lines are largely redundant — and a nav-heavy
  /// app would spend a chunk of the log buffer on them.
  Devtray navigation({int? maxVisits, bool? logNavigation}) {
    final nav = DevtrayNav.instance;
    if (maxVisits != null) nav.maxVisits = maxVisits;
    if (logNavigation != null) nav.logNavigation = logNavigation;
    return this;
  }

  // -------------------------------------------------------------- listeners
  //
  // The observe half of the API. Everything above configures what devtray
  // *captures*; these hand each captured item back so the app can act on it —
  // forward an error to a crash reporter, react to a 401, count freezes.
  //
  // Registered here they last the whole session, which is why these return
  // `Devtray` for the cascade rather than a disposer. For a listener scoped to
  // a widget, call the store's own `on…` method, which returns a
  // [DevtrayUnsubscribe] to call from `dispose`:
  //
  // ```dart
  // final _off = DevtrayNet.instance.onFailure(_retry);
  // @override void dispose() { _off(); super.dispose(); }
  // ```
  //
  // Every listener is observe-only. They run *after* the item is recorded and
  // cannot change or suppress it, so a callback that throws costs you the
  // callback — reported as an error line — and never the entry it was watching.

  /// Calls [listener] for every log line recorded.
  ///
  /// Fires for anything that reaches the log store, including captured
  /// `debugPrint` and errors. Use [onError] if you only want the errors.
  Devtray onLog(DevtrayListener<LogEntry> listener) {
    DevtrayLog.instance.onLog(listener);
    return this;
  }

  /// Calls [listener] for every error recorded — the crash-reporter hook.
  ///
  /// ```dart
  /// ..onError((e) => Sentry.captureException(e.error ?? e.message, stackTrace: e.stackTrace))
  /// ```
  ///
  /// Covers every route into the store at once: your own [Devtray.report] calls,
  /// the Flutter and platform error hooks `runDebugApp` installs, and failed
  /// requests forwarded from the network store.
  Devtray onError(DevtrayListener<LogEntry> listener) {
    DevtrayLog.instance.onError(listener);
    return this;
  }

  /// Calls [listener] when a request starts — before it has an outcome.
  Devtray onRequest(DevtrayListener<NetworkLogEntry> listener) {
    DevtrayNet.instance.onRequest(listener);
    return this;
  }

  /// Calls [listener] when a request completes, successfully or not.
  ///
  /// ```dart
  /// ..onResponse((r) {
  ///   if (r.statusCode == 401) authBloc.add(SessionExpired());
  /// })
  /// ```
  Devtray onResponse(DevtrayListener<NetworkLogEntry> listener) {
    DevtrayNet.instance.onResponse(listener);
    return this;
  }

  /// Calls [listener] only for requests that failed.
  ///
  /// Independent of the `errorReporting` mode, which governs only whether a
  /// failure also becomes a log line.
  Devtray onFailure(DevtrayListener<NetworkLogEntry> listener) {
    DevtrayNet.instance.onFailure(listener);
    return this;
  }

  /// Calls [listener] each time a route is entered.
  ///
  /// ```dart
  /// ..onScreen((v) => analytics.screenView(v.name))
  /// ```
  ///
  /// Sees routes from [DevtrayNavObserver] and hand-pushed screens from
  /// [Devtray.screen] alike, plus the return trip when a route is popped.
  Devtray onScreen(DevtrayListener<RouteVisit> listener) {
    DevtrayNav.instance.onScreen(listener);
    return this;
  }

  /// Calls [listener] when a route is left, with the finished visit — so
  /// [RouteVisit.duration] is populated.
  Devtray onScreenLeave(DevtrayListener<RouteVisit> listener) {
    DevtrayNav.instance.onScreenLeave(listener);
    return this;
  }

  /// Calls [listener] on every tracked state change, from any state library.
  Devtray onStateChange(DevtrayListener<StateChange> listener) {
    DevtrayState.instance.onStateChange(listener);
    return this;
  }

  /// Calls [listener] when a tracked state source reports an error.
  Devtray onStateError(DevtrayListener<TrackedSource> listener) {
    DevtrayState.instance.onStateError(listener);
    return this;
  }

  /// Calls [listener] when a UI freeze is detected.
  ///
  /// Requires [detectFreezes] — without it nothing is watching, and this never
  /// fires.
  Devtray onFreeze(DevtrayListener<FreezeEvent> listener) {
    DevtrayJank.instance.onFreeze(listener);
    return this;
  }

  /// Calls [listener] for each frame slower than the threshold.
  ///
  /// Runs **inside the frame pipeline** and can fire many times a second. Keep
  /// it to a counter; see [DevtrayJank.onSlowFrame].
  Devtray onSlowFrame(DevtrayListener<SlowFrameEvent> listener) {
    DevtrayJank.instance.onSlowFrame(listener);
    return this;
  }

  // --------------------------------------------------- removing listeners
  //
  // Statics, matching `log` and `screen`: unlike everything else on this class
  // these are for *use* rather than setup, and the moment you want one is
  // mid-session — a sign-out undoing whatever the signed-in session registered
  // — long after `configure` has run.
  //
  // Deliberately blunt. Each drops listeners you registered *and* any a package
  // or another part of the app registered. To undo only your own, hold the
  // [DevtrayUnsubscribe] the matching `on…` method returns and call that.
  //
  // All of them are unrelated to [enabled]: turning capture off already stops
  // every listener firing, because nothing is recorded. These drop the
  // registrations themselves, so they do not come back when capture is switched
  // on again.

  /// Drops [onLog] and [onError] listeners.
  static void clearLogListeners() => DevtrayLog.instance.clearListeners();

  /// Drops [onRequest], [onResponse] and [onFailure] listeners.
  static void clearNetworkListeners() => DevtrayNet.instance.clearListeners();

  /// Drops [onScreen] and [onScreenLeave] listeners.
  static void clearNavListeners() => DevtrayNav.instance.clearListeners();

  /// Drops [onStateChange] and [onStateError] listeners.
  static void clearStateListeners() => DevtrayState.instance.clearListeners();

  /// Drops [onFreeze] and [onSlowFrame] listeners.
  static void clearJankListeners() => DevtrayJank.instance.clearListeners();

  /// Drops every listener on **every** store, in one call.
  ///
  /// ```dart
  /// Devtray.clearListeners();
  /// ```
  ///
  /// The one to reach for on sign-out, or between tests — the stores are
  /// singletons, so a listener left behind would fire for every test after it.
  /// Use the per-store clears above when you mean to drop one subject's
  /// callbacks and leave the rest running.
  static void clearListeners() {
    clearLogListeners();
    clearNetworkListeners();
    clearNavListeners();
    clearStateListeners();
    clearJankListeners();
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
