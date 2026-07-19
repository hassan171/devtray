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

  // Attach build/user/screen context to everything captured from here on, so
  // an error carries who and where without the throw site knowing about it.
  installLogContext();

  // Watch for UI freezes for the whole session, not just while the Timeline is
  // on screen — the Debug tab's jank buttons freeze the UI from a different
  // tab, and a watchdog scoped to the Timeline page would miss them.
  //
  // Opt-in on purpose: a heartbeat timer plus a per-frame callback is the only
  // capture in the overlay with a real steady-state cost.
  FreezeWatchdog.instance.start();

  // Start persisting logs to disk. Everything captured from here on is written
  // as well as buffered, so the Logs page's session picker has past runs to
  // offer — including this one, once it ends.
  await installLogPersistence();

  // A relational store alongside the map-shaped ones — see NotesDbAdapter.
  await NotesDb.init();

  // ...and the same database again, discovered rather than hand-written: one
  // store per table, straight from `sqlite_master`. See SqfliteStorage.
  storageAdapters
    ..addAll(HiveStorage.boxes)
    ..addAll(await SqfliteStorage.tables(NotesDb.db));
}

void main() {
  // Keep background noise out of the inspector.
  NetworkLogStore.instance.excludedUrlPatterns.add('/health');

  // Feeds the State page from bloc. The observer is the only bloc-specific
  // adapter — StateInspector itself is library-agnostic. Already have an
  // observer? Chain it:
  //   Bloc.observer = DebugBlocObserver(next: MyObserver());
  Bloc.observer = DebugBlocObserver();

  // Show fields a source holds OUTSIDE its state. The inspector only ever sees
  // the current state, and Flutter has no reflection to go find the rest — so
  // you point at them. Registered from out here, CounterCubit needs no debug
  // import.
  //
  // (TodoBloc does the same thing the other way, by implementing
  // DebugInspectable — see counter_cubit.dart.)
  StateInspector.instance.inspect<CounterCubit>((c) => {'history': c.history, 'lastTouched': c.lastTouched});

  // The same mechanism, for a Riverpod notifier — `inspect` is keyed by type and
  // knows nothing about which library produced it. Nothing here is bloc- or
  // Riverpod-specific; that's the whole point.
  //
  // (It reads the notifier's own fields, not `state`: Riverpod protects that,
  // where a bloc's is public. The state is already on the page anyway — `inspect`
  // is for what ISN'T.)
  StateInspector.instance.inspect<Session>((s) => {'signIns': s.signIns, 'lastSignIn': s.lastSignIn});

  // Control how a state is DISPLAYED (not the data). TodoBloc's state is a
  // List<String>, which by default prints cramped: [todo 48, todo 48, todo 49].
  // Render one todo per line — but ONLY for TodoBloc, not every List<String>
  // state in the app. formatSource is keyed by the SOURCE type, so it's scoped
  // to this one cubit; format<T> would hit every source whose state is a T.
  StateInspector.instance.formatSource<TodoBloc>((state) {
    final todos = state as List<String>;
    return todos.isEmpty ? '(no todos)' : todos.map((t) => '• $t').join('\n');
  });

  // One call: installs the log/error capture Zone, wraps the app in the
  // overlay, and runs it. `enabled` gates both — with it false this is a plain
  // runApp() and the package leaves no trace in the tree.
  runDebugApp(
    // The Riverpod scope wraps the app, so the observer sees every provider.
    // Note what ISN'T here: no second State page, no choosing between libraries.
    // The bloc observer above and this one push into the same StateInspector,
    // and the page shows both — which is exactly what an app migrating from one
    // to the other needs.
    app: ProviderScope(
      observers: [const DebugRiverpodObserver()],
      child: MaterialApp(
        title: 'Notes — devtray example',
        // The app's own identity, deliberately unlike the overlay's blue/grey:
        // a screenshot should never leave you wondering where the host app ends
        // and the debug tool begins. Both modes, so the overlay's own dark
        // theme has something honest to sit on.
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const _Bootstrap(),
      ),
    ),
    enabled: kDebugMode,
    controller: debug,
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
      const NetworkDebugPage(onPreviewHtml: HtmlPreviewDialog.show),
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
            onPressed: debug.toggle,
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
        onDestinationSelected: (i) => setState(() => _tab = i),
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
