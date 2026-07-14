import 'package:debug_overlay/debug_overlay.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the overlay from our own triggers (the AppBar button below), on top
/// of the draggable launcher.
final debug = DebugOverlayController();

final dio = Dio()..interceptors.add(DebugDioInterceptor());
final httpClient = DebugHttpClient(http.Client());

/// Seeds one pref of each type, so the Storage page has something to edit.
Future<void> _seedPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.containsKey('seen_onboarding')) return;

  await prefs.setBool('seen_onboarding', true);
  await prefs.setInt('retry_count', 3);
  await prefs.setDouble('scroll_offset', 12.5);
  await prefs.setString('api_url', 'https://jsonplaceholder.typicode.com');
  await prefs.setStringList('recent_tags', ['flutter', 'dart']);
}

void main() {
  // Keep background noise out of the inspector.
  NetworkLogStore.instance.excludedUrlPatterns.add('/health');

  // One call: installs the log/error capture Zone, wraps the app in the
  // overlay, and runs it. `enabled` gates both — with it false this is a plain
  // runApp() and the package leaves no trace in the tree.
  runDebugApp(
    MaterialApp(
      title: 'debug_overlay example',
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      home: const HomeScreen(),
    ),
    enabled: kDebugMode,
    controller: debug,
    pages: [
      const NetworkDebugPage(),
      const LogsDebugPage(),
      const ErrorsDebugPage(),
      // Bundles everything into one bug report — pass `onShare:` to hand it to
      // share_plus if you want the OS share sheet.
      const ExportDebugPage(deviceInfoProvider: PluginDeviceInfoProvider()),
      // Browse and edit SharedPreferences live. Flip the lock to enable writes.
      const StorageDebugPage(adapters: [SharedPreferencesStorageAdapter()]),
      const MocksDebugPage(),
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
  _seedPrefs();
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
