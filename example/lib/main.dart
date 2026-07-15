import 'package:bloc/bloc.dart';
import 'package:debug_overlay/debug_overlay.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'counter_cubit.dart';
import 'users_box.dart';
import 'users_debug_page.dart';

/// Drives the overlay from our own triggers (the AppBar button below), on top
/// of the draggable launcher.
final debug = DebugOverlayController();

final dio = Dio()..interceptors.add(DebugDioInterceptor());

/// Live cubits, so the Blocs page has something to watch.
final counter = CounterCubit();
final todos = TodoBloc();
final httpClient = DebugHttpClient(http.Client());

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

/// Opens the Hive box. Awaited by [_Bootstrap] rather than in `main`, because
/// Hive needs the binding — and `runDebugApp` deliberately creates that *inside*
/// its capture Zone (a binding created outside it would leak errors past the
/// Zone's handler). So we let the app start, then open the box on the first
/// frame.
Future<void> _openHive() async {
  await Hive.initFlutter();
  Hive.registerAdapter(UserAdapter());
  await Hive.openBox<User>(usersBoxName);
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
    MaterialApp(
      title: 'debug_overlay example',
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      home: const _Bootstrap(),
    ),
    enabled: kDebugMode,
    controller: debug,
    pages: [
      const NetworkDebugPage(),
      // Combined logs + errors. Errors fold in as error-level rows (expand one
      // for its full report); the advanced filter's `Source`/`Level` fields
      // reproduce an errors-only view. Search + quick chips still on top.
      const LogsDebugPage(),
      // Two stores side by side: SharedPreferences (built in) and a TYPED,
      // hand-written Hive adapter — which is exactly why DebugStorageAdapter is
      // an interface rather than a bundled Hive implementation.
      StorageDebugPage(adapters: [const SharedPreferencesStorageAdapter(), UsersBoxAdapter()]),
      // A custom page — the Storage page can browse the Hive box generically,
      // but when you know what the data is, a purpose-built view beats a dump.
      const UsersDebugPage(),
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
  late final Future<void> _ready = _openHive();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('Hive failed to open:\n${snapshot.error}')));
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return const HomeScreen();
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('debug_overlay example'),
        actions: [IconButton(onPressed: debug.toggle, icon: const Icon(Icons.bug_report_outlined))],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 12,
          children: [
            const Text('Fire some requests, then open the overlay.'),
            // Goes through the same dio the overlay watches, so it lands on the
            // Network page AND fills the Hive box behind the Users tab.
            //
            // /users only has 10 real records, so they're fanned out to make a
            // list long enough to actually scroll.
            Wrap(
              spacing: 8,
              children: [
                for (final n in [10, 100, 1000])
                  FilledButton.tonalIcon(
                    onPressed: () => fetchAndStoreUsers(dio, count: n),
                    icon: const Icon(Icons.download, size: 16),
                    label: Text('$n users → Hive'),
                  ),
              ],
            ),
            FilledButton(onPressed: () => dio.get<dynamic>('https://jsonplaceholder.typicode.com/todos/1'), child: const Text('GET via dio')),
            FilledButton(
              onPressed: () => dio.post<dynamic>('https://jsonplaceholder.typicode.com/posts', data: {'title': 'hello', 'body': 'from dio', 'userId': 1}),
              child: const Text('POST via dio'),
            ),
            FilledButton(onPressed: () => httpClient.get(Uri.parse('https://jsonplaceholder.typicode.com/users/2')), child: const Text('GET via package:http')),
            FilledButton(
              // Fails — check the red row and its Error tab.
              onPressed: () =>
                  dio.get<dynamic>('https://jsonplaceholder.typicode.com/nope-404').catchError((_) => Response<dynamic>(requestOptions: RequestOptions())),
              child: const Text('Trigger a 404'),
            ),
            const Divider(height: 24),
            // Drive the cubits — watch them on the Blocs page. The Cubit's
            // transitions have no event; the Bloc's carry the one that caused
            // them.
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(onPressed: counter.increment, child: const Text('counter++')),
                OutlinedButton(onPressed: counter.decrement, child: const Text('counter--')),
                OutlinedButton(onPressed: counter.boom, child: const Text('cubit error')),
                // Changes a field WITHOUT emitting. The page only rebuilds on
                // emits, so this only appears after "Re-read fields" in the
                // detail pane — which is exactly why that button exists.
                OutlinedButton(onPressed: counter.touch, child: const Text('touch (no emit)')),
                OutlinedButton(onPressed: () => todos.add(TodoAdded('todo ${DateTime.now().second}')), child: const Text('add todo (Bloc)')),
                OutlinedButton(onPressed: () => todos.add(const TodoCleared()), child: const Text('clear todos')),
              ],
            ),
            const Divider(height: 24),
            FilledButton(
              onPressed: () {
                // All three land in the Logs page.
                debugPrint('debugPrint — captured by the debugPrint hook');
                print('print — captured by the Zone'); // ignore: avoid_print
                LogStore.instance.log('Tagged, levelled log', level: LogLevel.warning, tag: 'example');
              },
              child: const Text('Write some logs'),
            ),
            FilledButton(
              // Uncaught async — caught by the Zone, badges the launcher.
              onPressed: () => Future<void>.error(StateError('Something went wrong in a Future')),
              child: const Text('Throw an uncaught error'),
            ),
            FilledButton(
              // A 5xx also lands on the Errors page and badges the launcher.
              // The 404 button above does not — see the bell menu on the
              // Network page to change that.
              onPressed: () => dio.get<dynamic>('https://httpbin.org/status/500').catchError((_) => Response<dynamic>(requestOptions: RequestOptions())),
              child: const Text('Trigger a 500 (badges the launcher)'),
            ),
            OutlinedButton(onPressed: () => debug.showLauncher.value = !debug.showLauncher.value, child: const Text('Toggle the floating button')),
          ],
        ),
      ),
    );
  }
}
