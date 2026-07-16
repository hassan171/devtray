import 'package:devtray/devtray.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../app_services.dart' show counter, debug, dio, httpClient, todos;
import '../counter_cubit.dart';
import '../users_box.dart';

/// The demo harness — every overlay feature, on demand.
///
/// The other three tabs are the honest half of this example: a notes app that
/// fills the overlay by being used. This tab is the other half, and it doesn't
/// pretend otherwise. Some things a working app simply never does on purpose —
/// throw an uncaught error, ask for a 500, emit a cubit failure — and you still
/// need to see what the tool does when they happen.
///
/// Keeping them here, behind a labelled tab, is what lets the Notes/Users/
/// Profile tabs stay a real app instead of a button board.
class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        const _Intro(),
        const SizedBox(height: 12),

        _Section(
          title: 'Network',
          subtitle: 'Both transports feed one page — the overlay never asks which client you use.',
          children: [
            _Btn('GET via dio', () => dio.get<dynamic>('https://jsonplaceholder.typicode.com/todos/1')),
            _Btn(
              'POST via dio',
              () => dio.post<dynamic>(
                'https://jsonplaceholder.typicode.com/posts',
                data: {'title': 'hello', 'body': 'from dio', 'userId': 1},
              ),
            ),
            _Btn('GET via package:http', () => httpClient.get(Uri.parse('https://jsonplaceholder.typicode.com/users/2'))),
            // Fails — check the red row and its Error tab.
            _Btn(
              'A 404',
              () => dio.get<dynamic>('https://jsonplaceholder.typicode.com/nope-404').catchError((_) => Response<dynamic>(requestOptions: RequestOptions())),
            ),
            // A 5xx badges the launcher; the 404 above doesn't — see the bell
            // menu on the Network page to change which statuses count.
            _Btn(
              'A 500 (badges the launcher)',
              () => dio.get<dynamic>('https://httpbin.org/status/500').catchError((_) => Response<dynamic>(requestOptions: RequestOptions())),
            ),
          ],
        ),

        _Section(
          title: 'Storage',
          subtitle: '/users returns 10 real records — fanned out to make a list worth scrolling.',
          children: [
            for (final n in [10, 100, 1000]) _Btn('$n users → Hive', () => fetchAndStoreUsers(dio, count: n)),
          ],
        ),

        _Section(
          title: 'State',
          subtitle: 'A cubit emits without an event; a bloc carries the one that caused it.',
          children: [
            _Btn('counter++', counter.increment),
            _Btn('counter--', counter.decrement),
            _Btn('cubit error', counter.boom),
            // Changes a field WITHOUT emitting. The State page only rebuilds on
            // emits, so this only shows after "Re-read fields" in the detail
            // pane — which is exactly why that button exists.
            _Btn('touch (no emit)', counter.touch),
            _Btn('add todo (bloc)', () => todos.add(TodoAdded('todo ${DateTime.now().second}'))),
            _Btn('clear todos', () => todos.add(const TodoCleared())),
          ],
        ),

        _Section(
          title: 'Logs & errors',
          subtitle: 'Four routes into the Logs page, and an error no try/catch will see.',
          children: [
            _Btn('Write some logs', () {
              debugPrint('debugPrint — captured by the debugPrint hook');
              print('print — captured by the Zone'); // ignore: avoid_print
              LogStore.instance.log('Tagged, levelled log', level: LogLevel.warning, tag: 'example');
              // `dart:developer`'s log() is `external` — it goes straight to the
              // VM service, so there is NO hook that could capture it. This
              // `log` is the package's drop-in: same signature, still reaches
              // DevTools, and also records into the store. The only change a
              // real app makes is its import.
              log('developer.log — bridged, not captured', level: 900, name: 'example');
            }),
            // Uncaught async — nothing catches it but the Zone.
            _Btn('Uncaught error', () => Future<void>.error(StateError('Something went wrong in a Future'))),
          ],
        ),

        _Section(
          title: 'The overlay itself',
          children: [
            _Btn('Toggle the floating launcher', () => debug.showLauncher.value = !debug.showLauncher.value),
            _Btn('Open the overlay', debug.toggle),
          ],
        ),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Triggers for things the app won't do on its own. The other tabs "
                'fill the overlay just by being used — this one is the demo '
                'harness.',
                style: TextStyle(fontSize: 12, height: 1.4, color: scheme.onSurface.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _Section({required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 11, height: 1.35, color: scheme.onSurface.withValues(alpha: 0.5)),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: children),
            ],
          ),
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _Btn(this.label, this.onPressed);

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}
