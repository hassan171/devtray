import 'package:debug_overlay/debug_overlay.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hz_toast/hz_toast.dart';

/// Drives the overlay from our own triggers (the AppBar button below), on top
/// of the draggable launcher.
final debug = DebugOverlayController();

final dio = Dio()..interceptors.add(DebugDioInterceptor());
final httpClient = DebugHttpClient(http.Client());

void main() {
  // Keep background noise out of the inspector.
  NetworkLogStore.instance.excludedUrlPatterns.add('/health');

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DebugOverlay(
      // Only exists in debug builds. Swap for your own flag to ship it to a
      // staging release too.
      enabled: kDebugMode,
      controller: debug,
      presentation: DebugOverlayPresentation.dialog,
      theme: const DebugOverlayTheme(),
      pages: [
        const NetworkDebugPage(),
        // Any page you like — a plain widget builder is enough.
        DebugPage.builder(title: 'About', icon: Icons.info_outline, builder: (_) => const _AboutPage()),
      ],
      child: MaterialApp(
        title: 'debug_overlay example',
        theme: ThemeData(colorSchemeSeed: Colors.blue),
        // The copy buttons toast via hz_toast, which needs its initializer above
        // the app so it can render into the root overlay.
        builder: (context, child) => HzToastInitializer(child: child ?? const SizedBox()),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('debug_overlay example')),
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
            OutlinedButton(onPressed: () => debug.showLauncher.value = !debug.showLauncher.value, child: const Text('Toggle the floating button')),
          ],
        ),
      ),
    );
  }
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text('Custom pages are just widgets — register them with DebugPage.builder, or subclass DebugPage.'),
    );
  }
}
