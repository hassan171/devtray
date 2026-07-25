import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:devtray/devtray.dart';
// One import per integration. The core knows nothing about any of these — each
// lives in its own package, so an app only compiles the ones it actually uses.
// This example takes the lot because it demonstrates the lot; a real app takes
// two or three.
import 'package:devtray_bloc/devtray_bloc.dart';
import 'package:devtray_device/devtray_device.dart';
import 'package:devtray_hive/devtray_hive.dart';
import 'package:devtray_html/devtray_html.dart';
import 'package:devtray_prefs/devtray_prefs.dart';
import 'package:devtray_riverpod/devtray_riverpod.dart';
import 'package:devtray_sqflite/devtray_sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_services.dart';
import 'app_theme.dart';
import 'counter_cubit.dart';
import 'notes_db.dart';
import 'screens/notes_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/users_screen.dart';
import 'screens/debug_screen.dart';
import 'session_provider.dart';
import 'users_box.dart';

/// Seeds one pref of each type, so the Storage page has something to edit.
Future<void> _seedPref() async {
  final pref = await SharedPreferences.getInstance();
  if (pref.containsKey('seen_onboarding')) return;

  await pref.setBool('seen_onboarding', true);
  await pref.setInt('retry_count', 3);
  await pref.setDouble('scroll_offset', 12.5);
  await pref.setString('api_url', 'https://jsonplaceholder.typicode.com');
  await pref.setStringList('recent_tags', ['flutter', 'dart']);
}

/// Opens the local stores. Awaited by [_Bootstrap] rather than in `main`,
/// because they need the binding — and `runDebugApp` deliberately creates that
/// *inside* its capture Zone (a binding created outside it would leak errors
/// past the Zone's handler). So we let the app start, then open them on the
/// first frame.
/// Every store the Storage page shows.
///
/// Mutable and passed **by reference**, because SQLite discovery is async (it
/// has to ask the database what tables exist) while `pages:` is built
/// synchronously in `main`. The page holds this exact list, [_openStores] fills
/// the rest in before the first frame, and by the time the page can be opened
/// it's complete.
final List<DebugStorageAdapter> storageAdapters = [
  const SharedPreferencesStorageAdapter(),
  // The Hive boxes and the SQLite tables are appended by [_openStores] — both
  // need an open handle, which doesn't exist yet at this point.
];

Future<void> _openStores() async {
  await Hive.initFlutter();
  Hive.registerAdapter(UserAdapter());

  // Hive can't be discovered the way SQLite can — no box list, no schema, no
  // reflection — so the app declares each box as it opens it, at the one moment
  // it knows both the name and the type. Both boxes below are registered purely
  // by swapping `Hive.openBox` for `HiveStorage.openBox`; the box comes back
  // unchanged, so it stays a drop-in.

  // A TYPED box. Dart can't turn a User into named fields on its own, so this is
  // the one thing the wrapper can't infer: how to go to a map and back. Both
  // live on the model, next to each other — see User.toMap/User.fromMap.
  await HiveStorage.openBox<User>(
    usersBoxName,
    label: 'Users (Hive)',
    toMap: (u) => u.toMap(),
    fromMap: (key, map) => User.fromMap(int.parse(key), map),
  );

  // A box of PRIMITIVES needs nothing else at all — the values are already
  // showable and editable.
  final prefBox = await HiveStorage.openBox<String>('ui_prefs');
  if (prefBox.isEmpty) {
    await prefBox.putAll({
      'theme': 'dark',
      'density': 'compact',
      'last_route': '/home',
    });
  }

  // A relational store alongside the map-shaped ones — see NotesDbAdapter.
  await NotesDb.init();

  // ...and the same database again, discovered rather than hand-written: one
  // store per table, straight from `sqlite_master`. See SqfliteStorage.
  storageAdapters
    ..addAll(HiveStorage.boxes)
    ..addAll(await SqfliteStorage.tables(NotesDb.db));
}

/// The app itself, identical on both paths — with devtray and without.
///
/// One definition so the release path can't drift from the debug one: whatever
/// you see with the overlay attached is exactly what ships without it.
Widget _buildApp() {
  // The Riverpod scope wraps the app, so the observer sees every provider.
  // Note what ISN'T here: no second State page, no choosing between libraries.
  // The bloc observer in main() and this one push into the same DevtrayState,
  // and the page shows both — which is exactly what an app migrating from one
  // to the other needs.
  return ProviderScope(
    observers: [const DebugRiverpodObserver()],
    child: MaterialApp(
      // One line, and every log entry and network request gains a `screen`
      // field. No call sites of our own — this covers the pushed routes
      // (the note editor). The tab shell below cannot be observed, because
      // swapping an IndexedStack body pushes no route: see _HomeShell.
      navigatorObservers: [DevtrayNavObserver()],
      title: 'Notes — devtray example',
      // The app's own identity, deliberately unlike the overlay's blue/grey:
      // a screenshot should never leave you wondering where the host app ends
      // and the debug tool begins. Both modes, so the overlay's own dark theme
      // has something honest to sit on.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const _Bootstrap(),
    ),
  );
}

void main() {
  // Feeds the State page from bloc. Stays out here because it's an assignment
  // to bloc's own global, not devtray configuration — the observer is the only
  // bloc-specific adapter; DevtrayState itself is library-agnostic. Already
  // have an observer? Chain it:
  //   Bloc.observer = DebugBlocObserver(next: MyObserver());
  Bloc.observer = DebugBlocObserver();

  // Keeping devtray out of a release build is this `if`, not a flag on
  // runDebugApp. The call installs a capture Zone and replaces debugPrint and
  // FlutterError.onError before any flag could be read, so deciding out here is
  // the only way to make "off" mean *absent* rather than merely inert.
  if (!kDebugMode) {
    runApp(_buildApp());
    return;
  }

  // One call: installs the log/error capture Zone, wraps the app in the
  // overlay, and runs it.
  runDebugApp(
    _buildApp,
    // Everything the overlay's stores need, in one place.
    //
    // These used to be half a dozen `Something.instance.x = y` lines scattered
    // above this call, which was easy to lose track of and — for the ones that
    // check the capture switch — silently order-dependent. `configure` runs
    // after the capture hooks are installed, so a line logged from inside it is
    // captured rather than dropped.
    configure: (d) => d
      // Keep background noise out of the inspector.
      ..excludeUrls(['/health'])
      // Hide headers you don't want leaving the device — everywhere they'd
      // appear: the pane, copy-as-cURL, the JSON export, file sinks and the bug
      // report. Two modes:
      //   HeaderHiding.mask (default) keeps the name, blanks the value to
      //     ●●●●●● — a reader sees a token WAS sent, without seeing it.
      //   HeaderHiding.omit drops the header entirely, as if never sent.
      // This example uses omit; open a request on the Network page and the
      // hidden headers are simply absent, and gone from the cURL copy too.
      // `hideAllHeaders: true` covers every header at once.
      ..network(
        headerHiding: HeaderHiding.omit,
        hideHeaders: {'authorization', 'user-agent'},
        // hideHeader: (h) => h.contains('acc'), // any header with "acc" in its name
      )
      // Ambient context on every log line and error. The payoff is the errors
      // nobody anticipated: a crash report that says who it happened to,
      // without the throw site knowing anything about it.
      ..context({'build': '1.4.2+318', 'flavor': 'example', 'userId': 'anonymous'})
      // The `screen` field comes from DevtrayNavObserver now, installed on the
      // MaterialApp — no enricher needed, and it lands on network requests as
      // well as log lines. Open any request's Context tab to see it.
      //
      // Route changes also draw as spans on the Timeline's `nav` lane, which is
      // what makes "the 500 happened right after I opened the editor" a thing
      // you see rather than infer.
      ..navigation(logNavigation: true)
      ..enrich('session', () => {'uptime': '${DateTime.now().difference(startedAt).inSeconds}s'})
      // Show fields a source holds OUTSIDE its state. The inspector only ever
      // sees the current state, and Flutter has no reflection to go find the
      // rest — so you point at them. Registered here, neither class needs a
      // debug import of its own.
      //
      // `inspectAll` where several are registered together; `inspect<T>` is
      // identical for a single one. Each entry carries its own type, which is
      // why they are `Inspect` objects — the registry is keyed by type, and a
      // list of bare callbacks would erase it.
      //
      // Note the second is a Riverpod notifier and the first a bloc cubit:
      // `inspect` knows nothing about which library produced them, which is the
      // whole point. (TodoBloc does the same thing the other way, by
      // implementing DebugInspectable — see counter_cubit.dart.)
      ..inspectAll([
        Inspect<CounterCubit>((c) => {'history': c.history, 'lastTouched': c.lastTouched}),
        Inspect<Session>((s) => {'signIns': s.signIns, 'lastSignIn': s.lastSignIn}),
      ])
      // Control how a state is DISPLAYED (not the data). TodoBloc's state is a
      // List<String>, which by default prints cramped. formatSource is keyed by
      // the SOURCE type, so this is scoped to this one bloc; formatState<T>
      // would hit every source whose state is a T.
      ..formatSource<TodoBloc>((state) {
        final todos = state as List<String>;
        return todos.isEmpty ? '(no todos)' : todos.map((t) => '• $t').join('\n');
      })
      // Watch for UI freezes for the whole session, not just while the Timeline
      // page is mounted — the Debug tab's jank buttons freeze the UI from a
      // different tab, and a page-scoped watchdog would miss them.
      ..detectFreezes()
      // Everything above configures what devtray RECORDS. The `on…` methods
      // hand each recorded item back, so the app can act on it — this is where
      // a real app forwards to Sentry, or reacts to a 401 by signing out.
      //
      // Not the same as the `tick` notifiers the pages listen to: those are a
      // coalesced "something changed" with no payload, so a burst of ten
      // requests fires once and finding out what arrived means diffing the
      // buffer. These carry the item itself, one call per capture.
      //
      // Observe-only — they run after the item is recorded and cannot change or
      // suppress it, and one that throws costs you the callback rather than the
      // entry it was watching.
      //
      // Note these report with `Zone.root.print`, not `print` or `debugPrint`.
      // runDebugApp captures BOTH of those into the log store, so a log
      // listener printing with either would feed the store it is listening to.
      // `Zone.root.print` is the one route out to the console that capture
      // cannot see — the same escape hatch runDebugApp uses for errors thrown
      // inside its own zone. A real app forwarding to Sentry or a metrics
      // client never touches this, since neither goes through print.
      ..onError((e) => Zone.root.print('[example] would report to Sentry: ${e.message}'))
      ..onFailure((r) => Zone.root.print('[example] request failed: ${r.method} ${r.uri.path} → ${r.statusCode}'))
      // Registered here these last the whole session. For one scoped to a
      // widget, call the store's own method — DevtrayNav.instance.onScreen(...)
      // returns a DevtrayUnsubscribe to call from dispose().
      ..onScreen((v) => Zone.root.print('[example] would send a screen view: ${v.name}'))
      // Whether anything is recorded. kDebugMode is the default, so this line
      // changes nothing in the example — it's spelled out because it's half of
      // a pair with `launcher` below, and the interesting combination is the
      // one an app ships on purpose: `..capture(true)..launcher(false)` records
      // in a release build for QA to pull logs off, with no visible affordance.
      ..capture(kDebugMode)
      // The floating bug button. True is the default, so this line changes
      // nothing — it's here because the Debug tab toggles it at runtime, and
      // this is the one place that says where the starting value comes from.
      // Pass false for an app with no visible affordance: Devtray.open() from
      // your own trigger is then the only way in.
      ..launcher(true)
      // Logs leave memory and land on disk, so the Logs page's session picker
      // has past runs to offer. Async because opening the directory touches the
      // filesystem; runDebugApp awaits it before running the app, so bootstrap
      // lines still make it into the file.
      ..logToAsync(
        openFileLogSink,
        // Batched is the default; spelled out because it's the setting worth
        // knowing about. Short interval so the example's files fill visibly.
        policy: const FlushPolicy.batched(size: 25, interval: Duration(seconds: 2)),
      )
      // A second destination on the same buffer — the shape of shipping logs
      // somewhere. Not a real upload: see UploadLogSink.
      ..logTo(UploadLogSink())
      // Requests land on disk too, in their own file per run. Written on
      // completion, plus anything still in flight when the app is backgrounded.
      ..networkToAsync(openFileNetworkSink),
    // The Riverpod scope wraps the app, so the observer sees every provider.
    // Note what ISN'T here: no second State page, no choosing between libraries.
    // The bloc observer above and this one push into the same DevtrayState,
    // and the page shows both — which is exactly what an app migrating from one
    // to the other needs.
    pages: [
      // `onPreviewHtml` is what turns the HTML preview button on. The core has
      // no HTML renderer — it doesn't depend on flutter_html — so without a
      // previewer the button isn't drawn at all. devtray_html supplies one.
      // Requests, logs and state on one axis. First, because it's the page that
      // answers "what just happened" — the others answer "what happened to
      // *this*". Owns no data: it reads the same three stores the tabs below
      // read, so adding it costs nothing until you open it.
      //
      // Pair it with the load generator on the Debug tab — that's what makes
      // the lanes worth looking at.
      // Note `detectFreezes` is NOT set here: the watchdog is started for the
      // whole session in _openStores instead. The flag scopes it to while this
      // page is mounted, which would miss a freeze triggered from another tab —
      // exactly what the Debug tab's jank buttons do.
      const TimelineDebugPage(onPreviewHtml: HtmlPreviewDialog.show),
      const NetworkDebugPage(
        onPreviewHtml: HtmlPreviewDialog.show,
        // A folder button beside the search field, opening past runs read-only
        // — the same interaction the Logs page offers for saved log sessions.
        sessionSource: DeferredRequestSessions(),
      ),
      // Combined logs + errors. Errors fold in as error-level rows (expand one
      // for its full report); the advanced filter's `Source`/`Level` fields
      // reproduce an errors-only view. Search + quick chips still on top.
      //
      // `sessionSource` adds the other half: logs are written to disk as they
      // happen (see installLogPersistence), and this is what lets you open a
      // *previous run* and read it back. Without it the page is live-only,
      // which is what it was before and still is for an app that wants that.
      //
      // Deferred for the same reason as the storage adapters below — opening
      // the log directory is async, and `pages:` is built now.
      LogsDebugPage(sessionSource: DeferredLogSessions()),
      // Stores of genuinely different shapes — a plain key/value one, a typed
      // object box, and SQL tables — so the store list has something to choose
      // between, and DebugStorageAdapter has something to prove.
      //
      // Every store hooks up without a hand-written adapter, each in the way its
      // library allows:
      //  * **Discovered** — `SqfliteStorage.tables(db)`. SQLite describes
      //    itself, so handing over the Database is enough: every table shows up.
      //  * **Wrapped** — `HiveStorage.openBox(...)`. Hive describes nothing, so
      //    the app declares each box as it opens it. Free for primitives; a
      //    typed box supplies `toMap`/`fromMap`, the one thing Dart can't infer.
      //
      // Write an adapter by hand (see NotesDbAdapter) when only *you* know what
      // the data means — `pinned` is 0/1, `status` is one of four strings. No
      // schema says that, so no generic reader can enforce it.
      //
      // Passed by reference, NOT spread: both routes are async and fill this
      // list during bootstrap, while `pages:` is built now. Spreading would copy
      // it while it's still empty and none of those stores would ever appear.
      StorageDebugPage(adapters: storageAdapters),
      // A custom page — the Storage page can browse the Hive box generically,
      // but when you know what the data is, a purpose-built view beats a dump.
      // const UsersDebugPage(),
      // Live state + the change history behind it, for any state library.
      const StateDebugPage(),
      VisualDebugPage(),
      // Real device/OS/app facts, plus our own section merged in.
      const DeviceDebugPage(
        provider: CompositeDeviceInfoProvider([
          PluginDeviceInfoProvider(),
          StaticDeviceInfoProvider([
            DeviceInfoSection('Environment', {'API': 'jsonplaceholder.typicode.com', 'Flavor': 'example'}),
          ]),
        ]),
      ),
      // Bundles everything into one bug report — pass `onShare:` to hand it to
      // share_plus if you want the OS share sheet.
      const ExportDebugPage(deviceInfoProvider: PluginDeviceInfoProvider()),
      // Any page you like — a plain widget builder is enough.
      // DebugPage.builder(
      //   title: 'About',
      //   icon: Icons.info_outline,
      //   builder: (_) =>
      //       Padding(padding: EdgeInsets.all(16), child: Text('Custom pages are just widgets — register them with DebugPage.builder, or subclass DebugPage.')),
      // ),
    ],
  );

  // After runDebugApp — it calls ensureInitialized() inside the Zone, so the
  // binding (and therefore the SharedPreferences channel) exists by now.
  _seedPref();
}

/// Holds the app back until Hive is open, so nothing touches a closed box.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<void> _ready = _openStores();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('A store failed to open:\n${snapshot.error}')));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return const HomeScreen();
      },
    );
  }
}

/// A small, believable notes app — which is the only honest way to demonstrate
/// a tool that watches an app.
///
/// The old version of this screen was twenty buttons in a column: "GET via
/// dio", "Trigger a 404", "Write some logs". They filled the overlay's pages,
/// but they taught the wrong thing — that you drive a debug tool by hand. You
/// don't. You use your app, and the tool fills up on its own.
///
/// So the triggers are gone, and the same features now come out of ordinary
/// use:
///
///  * **Network** — pull-to-refresh on Users fetches from the API.
///  * **Storage** — every note you write is a SQLite row; every user fetched is
///    a Hive record. Edit one from the Storage page and the app updates behind
///    the overlay, because it's the same store.
///  * **State** — the Riverpod session and the bloc todo list, on Profile.
///  * **Logs** — the app logs what it does, as an app does.
///
/// The one thing this costs: a few overlay features have no natural trigger in
/// a notes app — an uncaught async error, a 500, a cubit that throws. Rather
/// than bolt a "Debug" tab back on and undo the point, they're reachable from
/// the Profile tab's developer section, where a real app would keep them.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _titles = ['Notes', 'Users', 'Profile', 'Debug'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Open the debug overlay',
            onPressed: Devtray.toggle,
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
      ),
      body: IndexedStack(
        // IndexedStack, not a swap: each tab keeps its scroll position and its
        // state across switches, the way a real app's tabs do.
        index: _tab,
        children: const [NotesScreen(), UsersScreen(), ProfileScreen(), DebugScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          // The half an observer cannot see. Switching tabs swaps an
          // IndexedStack body — no route is pushed, so there is nothing to
          // observe, and only the app knows it happened. One line where the
          // swap already is; it feeds the same history the observer does.
          Devtray.screen(_titles[i].toLowerCase());
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.note_outlined), selectedIcon: Icon(Icons.note), label: 'Notes'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Users'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          NavigationDestination(icon: Icon(Icons.bug_report_outlined), selectedIcon: Icon(Icons.bug_report), label: 'Debug'),
        ],
      ),
    );
  }
}
