// A minimal devtray example: the overlay, four core pages, and buttons that
// generate something for each one to show.
//
// Deliberately uses *only* the core package — no dio, no hive, no sqflite — so
// it runs with zero extra dependencies. For an app wired to every integration,
// see the `example/` directory at the repo root:
// https://github.com/hassan171/devtray/tree/main/example

import 'dart:math';

import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';

void main() => runDebugApp(
  () => const MyApp(),

  // Everything the stores need, in one place. Runs before capture starts.
  configure: (d) => d
    ..context({'flavor': 'example', 'build': '1.0.0'})
    ..detectFreezes(),

  pages: const [
    TimelineDebugPage(),
    NetworkDebugPage(),
    LogsDebugPage(),
    ExportDebugPage(),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'devtray example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _random = Random();
  var _requestCount = 0;

  /// Feeds the Network page without an HTTP client. `add` opens an entry and
  /// `complete` closes it — exactly what the devtray_dio and devtray_http
  /// adapters do around a real request.
  ///
  /// `add` returns null when the URL is excluded from the log, so the result
  /// has to be null-checked before completing.
  void _fakeRequest({required bool fail}) {
    final n = ++_requestCount;
    final entry = DevtrayNet.instance.add(
      method: fail ? 'POST' : 'GET',
      uri: Uri.parse('https://api.example.com/items/$n'),
      requestHeaders: const {'accept': 'application/json'},
    );
    if (entry == null) return;

    Future.delayed(Duration(milliseconds: 120 + _random.nextInt(400)), () {
      DevtrayNet.instance.complete(
        entry.id,
        status: fail ? NetworkLogStatus.failed : NetworkLogStatus.success,
        statusCode: fail ? 500 : 200,
        responseHeaders: const {
          'content-type': ['application/json'],
        },
        responseBody: fail ? '{"error":"internal"}' : '{"id":$n,"ok":true}',
      );
    });
  }

  /// Blocks the UI thread. The Timeline's jank lane catches it because
  /// `detectFreezes()` is on in `configure` above.
  void _freeze() {
    final until = DateTime.now().add(const Duration(milliseconds: 800));
    while (DateTime.now().isBefore(until)) {
      // Busy-wait — a real freeze, not an await.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('devtray example')),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Tap the floating button to open the tools panel.',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton(
                onPressed: () => _fakeRequest(fail: false),
                child: const Text('Request'),
              ),
              FilledButton.tonal(
                onPressed: () => _fakeRequest(fail: true),
                child: const Text('Failing request'),
              ),
              OutlinedButton(
                onPressed: () => Devtray.log(
                  'Something worth noting',
                  level: LogLevel.info,
                  tag: 'demo',
                  fields: {'count': _requestCount},
                ),
                child: const Text('Log'),
              ),
              OutlinedButton(
                onPressed: () => Devtray.report(
                  StateError('Simulated failure'),
                  context: 'the demo button',
                ),
                child: const Text('Report error'),
              ),
              OutlinedButton(onPressed: _freeze, child: const Text('Freeze 800ms')),
            ],
          ),
        ],
      ),
    ),
  );
}
