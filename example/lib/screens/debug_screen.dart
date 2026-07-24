import 'package:devtray/devtray.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../app_services.dart' show UploadLogSink, counter, dio, httpClient, logSessions, todos;
import '../counter_cubit.dart';
import '../load_generator.dart';
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

        const _LoadSection(),

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
              Devtray.log('Tagged, levelled log', level: LogLevel.warning, tag: 'example');
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
          title: 'Jank',
          subtitle: 'Freeze the UI on purpose — the jank lane on the Timeline is the only way to see it worked.',
          children: [
            // Short enough not to feel broken, long enough to clear the 250ms
            // threshold comfortably.
            _Btn('Freeze 500ms', () => LoadGenerator.instance.freezeUi(const Duration(milliseconds: 500))),
            // Unmistakable. The app will not respond while this runs — that is
            // the point, and the lane should show a fat red bar afterwards.
            _Btn('Freeze 2s', () => LoadGenerator.instance.freezeUi(const Duration(seconds: 2))),
            // Renders, but late: caught by the frame timings rather than the
            // heartbeat, and drawn as a run of marks rather than one bar.
            //
            // 80ms per frame, comfortably over the 32ms threshold — a margin
            // thin enough to sit near the line would make "did it work?"
            // ambiguous, which is the wrong thing for a demo button.
            _Btn(
              'Stutter (slow frames)',
              () => LoadGenerator.instance.stutterUi(frames: 20, each: const Duration(milliseconds: 80)),
            ),
          ],
        ),

        _Section(
          title: 'Log context',
          subtitle: 'Every line already carries build, flavor, userId and screen — open any row to see its Fields.',
          children: [
            // Ambient: nothing else changes, but every subsequent line differs.
            _Btn('Sign in (sets userId)', () {
              Devtray.setContext('userId', 'u-4821');
              Devtray.log('Signed in', level: LogLevel.info, tag: 'auth');
            }),
            _Btn('Sign out', () {
              Devtray.setContext('userId', 'anonymous');
              Devtray.log('Signed out', level: LogLevel.info, tag: 'auth');
            }),
            // The tab bar and the note editor already move the screen field —
            // one via Devtray.screen, the other via DevtrayNavObserver. This
            // names a screen the app doesn't have, so you can watch one value
            // reach a log line AND the next request's Context tab without
            // leaving this tab.
            _Btn('Set screen to "checkout"', () {
              Devtray.screen('checkout');
              Devtray.log('Now on checkout', tag: 'nav');
            }),
            // Per-call: one line, fields nothing else has.
            _Btn('Log with per-call fields', () {
              Devtray.log(
                'Checkout failed',
                level: LogLevel.error,
                tag: 'checkout',
                fields: {'cartId': 991, 'step': 'payment', 'amount': 42.50},
              );
            }),
            // Scoped: applies inside the block and is gone after it.
            _Btn('A scoped context (withContext)', () async {
              await Devtray.withContext({'orderId': 'ord-7731'}, () async {
                Devtray.log('Submitting order', tag: 'checkout');
                await Future<void>.delayed(const Duration(milliseconds: 50));
                Devtray.log('Order confirmed', level: LogLevel.info, tag: 'checkout');
              });
              // No orderId on this one — the scope closed.
              Devtray.log('Back on the cart', tag: 'checkout');
            }),
            // The failure path: the line must survive its decoration breaking.
            _Btn('Break an enricher', () {
              DevtrayLog.instance.addEnricher('broken', () => throw StateError('this enricher is broken'));
              Devtray.log('First line after breaking it', tag: 'demo');
              Devtray.log('Second — enricher now disabled', tag: 'demo');
            }),
          ],
        ),

        _Section(
          title: 'Log persistence',
          subtitle: 'Logs are written to disk as they happen — the folder icon on the Logs page opens past runs.',
          children: [
            // Forces the batch out now rather than waiting for the interval, so
            // "start the generator, flush, open the picker" works immediately.
            _Btn('Flush to disk now', () async {
              await DevtrayExport.instance.flush();
              Devtray.log(
                'Flushed — ${UploadLogSink.batchesSent} batches to the simulated uploader '
                '(${UploadLogSink.entriesSent} entries)',
                level: LogLevel.info,
                tag: 'export',
              );
            }),
            _Btn('Where are the files?', () async {
              final dir = logSessions?.directory.path;
              Devtray.log(dir == null ? 'Log persistence is not installed' : 'Log files: $dir', tag: 'export');
            }),
            // The state a batched policy is meant to survive.
            _Btn('Simulate a crash (uncaught)', () {
              Devtray.log('About to throw — this line should survive in the file', level: LogLevel.warning, tag: 'export');
              Future<void>.error(StateError('Crash simulation — check the saved session'));
            }),
          ],
        ),

        _Section(
          title: 'The overlay itself',
          children: [
            _Btn('Toggle the floating launcher', () => Devtray.showLauncher = !Devtray.showLauncher),
            _Btn('Open the overlay', Devtray.toggle),
          ],
        ),
      ],
    );
  }
}

/// The load generator's controls.
///
/// Its own widget rather than another [_Section] because it's the one control
/// here with *state* — it has to show whether it's running and how much it has
/// produced. Everything else on this screen is a fire-and-forget button.
class _LoadSection extends StatelessWidget {
  const _LoadSection();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final load = LoadGenerator.instance;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Continuous load',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
                  ),
                  const Spacer(),
                  // The live readout. Rebuilds on its own notifier, so the rest
                  // of this screen isn't rebuilt several times a second by it.
                  ValueListenableBuilder<bool>(
                    valueListenable: load.isRunning,
                    builder: (context, running, _) => ValueListenableBuilder<int>(
                      valueListenable: load.emitted,
                      builder: (context, count, _) => Row(
                        children: [
                          if (running)
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                            ),
                          if (running) const SizedBox(width: 6),
                          Text(
                            running ? '$count events' : 'idle',
                            style: TextStyle(
                              fontSize: 11,
                              fontFeatures: const [FontFeature.tabularFigures()],
                              color: scheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Timers driving requests, logs and state changes at once — what the '
                'overlay looks like under real traffic rather than one button press.',
                style: TextStyle(fontSize: 11, height: 1.35, color: scheme.onSurface.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: load.isRunning,
                    builder: (context, running, _) => FilledButton.tonal(
                      onPressed: load.toggle,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12),
                        backgroundColor: running ? scheme.errorContainer : null,
                        foregroundColor: running ? scheme.onErrorContainer : null,
                      ),
                      child: Text(running ? 'Stop' : 'Start'),
                    ),
                  ),
                  // Fills past the 1000-line log cap in one go, so eviction and
                  // searching a full buffer are both reachable immediately.
                  _Btn('Burst (1200 logs)', () => LoadGenerator.instance.burst()),
                  _Btn('Flood logs only', () => LoadGenerator.instance.burst(requests: 0, logs: 2000)),
                ],
              ),
            ],
          ),
        ),
      ),
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
