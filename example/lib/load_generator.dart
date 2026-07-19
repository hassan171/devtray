import 'dart:async';
import 'dart:math';

import 'package:devtray/devtray.dart';
import 'package:flutter/foundation.dart';

import 'app_services.dart' show counter, dio, httpClient, todos;
import 'counter_cubit.dart';

/// Drives continuous traffic at the overlay, so it can be watched under load
/// rather than one hand-pressed button at a time.
///
/// The tool's hard parts only show up in bulk: a ring buffer evicting, a search
/// filtering a full buffer per keystroke, a list rebuilding while rows stream
/// in, the launcher dragging over a busy app. None of that is reachable by
/// tapping "GET via dio" once.
///
/// Two independent timers, because the two feeds have genuinely different
/// shapes. Network is slow and bursty — a handful of in-flight requests
/// resolving out of order, some failing. Logs and state are fast and cheap, and
/// the interesting question there is what a *flood* does. Running them on one
/// timer would tie the flood's rate to the network's.
///
/// Deliberately not started automatically — see [LoadGenerator.start]. An
/// example app that opens firing requests is one you can't read.
class LoadGenerator {
  LoadGenerator._();
  static final LoadGenerator instance = LoadGenerator._();

  Timer? _networkTimer;
  Timer? _logTimer;

  /// Seeded, not `Random()`: a reproducible sequence means a stall you saw once
  /// is a stall you can see again.
  final Random _random = Random(1337);

  int _tick = 0;

  /// Whether either feed is running. Drives the button labels.
  final ValueNotifier<bool> isRunning = ValueNotifier<bool>(false);

  /// How many requests, logs and state changes have been produced this run.
  /// Shown in the UI so "is it actually doing anything" needs no guessing.
  final ValueNotifier<int> emitted = ValueNotifier<int>(0);

  /// Starts both feeds.
  ///
  /// [networkPeriod] is deliberately slower than [logPeriod]: real requests take
  /// real time, and firing them faster than they resolve just queues them up in
  /// the HTTP client rather than telling you anything about the overlay.
  void start({
    Duration networkPeriod = const Duration(milliseconds: 900),
    Duration logPeriod = const Duration(milliseconds: 250),
  }) {
    if (isRunning.value) return;

    _networkTimer = Timer.periodic(networkPeriod, (_) => _fireNetwork());
    _logTimer = Timer.periodic(logPeriod, (_) => _fireLogsAndState());
    isRunning.value = true;

    LogStore.instance.log(
      'Load generator started — network every ${networkPeriod.inMilliseconds}ms, '
      'logs every ${logPeriod.inMilliseconds}ms',
      level: LogLevel.info,
      tag: 'load',
    );
  }

  void stop() {
    if (!isRunning.value) return;

    _networkTimer?.cancel();
    _logTimer?.cancel();
    _networkTimer = null;
    _logTimer = null;
    isRunning.value = false;

    LogStore.instance.log('Load generator stopped after ${emitted.value} events', level: LogLevel.info, tag: 'load');
  }

  void toggle() => isRunning.value ? stop() : start();

  /// A burst, without the timers — for "fill the buffer, then search it".
  ///
  /// The ring buffers hold 500 requests and 1000 log lines, so this defaults to
  /// enough log lines to force eviction. Requests are kept far lower: 300 real
  /// in-flight HTTP calls would spend a minute resolving and mostly measure
  /// jsonplaceholder's rate limiter.
  Future<void> burst({int requests = 12, int logs = 1200}) async {
    LogStore.instance.log('Burst: $requests requests, $logs log lines', level: LogLevel.info, tag: 'load');

    for (var i = 0; i < logs; i++) {
      _emitLog(i);
    }
    for (var i = 0; i < requests; i++) {
      _fireNetwork();
    }
    emitted.value += logs + requests;
  }

  /// One request, cycling through the states the Network page renders.
  ///
  /// The point is the *mix*. A page that only ever shows green 200s proves
  /// nothing about how a failed row, a pending spinner or a slow request looks
  /// next to its neighbours — and pending-vs-complete is exactly what the row
  /// keying and the coalesced store tick have to get right.
  void _fireNetwork() {
    final n = _tick++;
    emitted.value++;

    // Weighted rather than uniform: mostly-succeeding traffic with occasional
    // failures is what a real app looks like, and it's the case where a rare
    // red row has to stay findable among many green ones.
    final roll = _random.nextInt(100);

    if (roll < 45) {
      // Plain GET — small JSON body.
      _swallow(dio.get<dynamic>('https://jsonplaceholder.typicode.com/todos/${(n % 200) + 1}'));
    } else if (roll < 60) {
      // POST with a request body, so the cURL/body tabs have something in them.
      _swallow(
        dio.post<dynamic>(
          'https://jsonplaceholder.typicode.com/posts',
          data: {'title': 'load $n', 'body': 'generated at ${DateTime.now().toIso8601String()}', 'userId': n % 10},
        ),
      );
    } else if (roll < 72) {
      // The other transport, so both adapters stay exercised.
      _swallow(httpClient.get(Uri.parse('https://jsonplaceholder.typicode.com/users/${(n % 10) + 1}')));
    } else if (roll < 80) {
      // A large-ish response — /photos is ~5000 records. This is the payload
      // that made the detail pane's pretty-printing and HTML sniffing hurt.
      _swallow(dio.get<dynamic>('https://jsonplaceholder.typicode.com/photos'));
    } else if (roll < 88) {
      // 404 — a failure that does NOT badge the launcher by default.
      _swallow(dio.get<dynamic>('https://jsonplaceholder.typicode.com/nope-$n'));
    } else if (roll < 94) {
      // 500 — a failure that does badge it, and lands in the Logs page too.
      _swallow(dio.get<dynamic>('https://httpbin.org/status/500'));
    } else {
      // A deliberately slow request, so there is something still *pending* while
      // later ones complete around it — the out-of-order case.
      _swallow(dio.get<dynamic>('https://httpbin.org/delay/3'));
    }
  }

  /// Logs of every level and a state change, several times a second.
  void _fireLogsAndState() {
    final n = _tick++;
    emitted.value++;

    _emitLog(n);

    // State changes on the same beat, so the State page is busy while the Logs
    // page is. Every third tick, so the two feeds aren't locked in step.
    if (n % 3 == 0) {
      counter.increment();
    } else if (n % 7 == 0) {
      todos.add(TodoAdded('generated todo $n'));
    }
  }

  /// One log line, cycling through every level, tag and shape the page renders.
  void _emitLog(int n) {
    final store = LogStore.instance;

    switch (n % 8) {
      case 0:
        store.log('Cache hit for key user:${n % 50}', level: LogLevel.debug, tag: 'cache');
      case 1:
        store.log('Sync completed in ${_random.nextInt(400)}ms', level: LogLevel.info, tag: 'sync');
      case 2:
        store.log('Retry ${n % 3 + 1}/3 for pending upload', level: LogLevel.warning, tag: 'upload');
      case 3:
        // A long, multi-line message — the row has to stay one line collapsed
        // and readable expanded.
        store.log(
          'Payload rejected by validator\n'
          '  field: email\n'
          '  value: not-an-email-$n\n'
          '  rule: RFC 5322',
          level: LogLevel.error,
          tag: 'validation',
        );
      case 4:
        // Untagged, so the tag filter has entries that don't match any tag.
        store.log('Frame budget exceeded: ${16 + _random.nextInt(30)}ms');
      case 5:
        // Goes through the debugPrint hook rather than the store directly.
        debugPrint('debugPrint from the load generator — tick $n');
      case 6:
        // A reported error with a real stack, so the Logs detail has one to show.
        store.report(
          StateError('Simulated failure #$n'),
          stackTrace: StackTrace.current,
          context: 'LoadGenerator._emitLog',
        );
      case 7:
        store.log('User ${n % 20} tapped "Save"', level: LogLevel.info, tag: 'analytics');
    }
  }

  /// Failures here are the *point* — they're what fills the red rows — so they
  /// must not become uncaught errors that the Zone reports a second time.
  void _swallow(Future<Object?> future) {
    unawaited(future.catchError((Object _) => null));
  }
}
