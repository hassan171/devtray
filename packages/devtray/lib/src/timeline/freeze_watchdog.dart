import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/devtray_kill_switch.dart';

/// One period during which the UI isolate did not respond.
class FreezeEvent {
  final DateTime start;
  final DateTime end;

  /// How long the isolate was unresponsive.
  final Duration duration;

  const FreezeEvent({required this.start, required this.end, required this.duration});
}

/// One rendered frame that took too long, from `addTimingsCallback`.
///
/// Distinct from a [FreezeEvent]: a slow frame *rendered*, just late. A freeze
/// is time in which nothing rendered at all.
class SlowFrameEvent {
  final DateTime at;

  /// Time spent building the widget tree.
  final Duration build;

  /// Time spent rasterising it.
  final Duration raster;

  const SlowFrameEvent({required this.at, required this.build, required this.raster});

  Duration get total => build + raster;
}

/// Detects periods where the UI isolate stopped responding, and frames that
/// rendered too slowly.
///
/// ## What this can and cannot see
///
/// **A frozen isolate cannot detect its own freeze.** While the main isolate is
/// blocked — a synchronous `jsonDecode`, a tight loop, a blocking plugin call —
/// no timer fires, no frame callback runs, and no code here executes. So this is
/// a *retrospective* detector: the heartbeat below notices, on its next tick,
/// that far more wall-clock time passed than the interval it asked for, and
/// reports the gap after the fact.
///
/// Consequences worth being explicit about:
///
///  * A freeze is only reported **once it ends**. A terminal hang — the app
///    never recovers — is reported by nothing, because nothing runs to report
///    it. Catching those needs a watchdog isolate, which is a much larger piece
///    of machinery and doesn't work on web.
///  * There is **no stack trace**. By the time the gap is measurable, whatever
///    caused it has already returned. Attribution here is circumstantial: the
///    timeline shows what else happened in the same window.
///  * `addTimingsCallback` alone is not enough, which is why both are used. It
///    only fires for frames that *rendered*, so a three-second block produces no
///    timings at all — the case you most want is the one it is blind to.
///
/// ## Cost
///
/// A periodic timer at [heartbeatInterval] plus a per-frame callback. Small,
/// but the first thing in the overlay with a real steady-state cost — so it is
/// **opt-in**: nothing runs until [start] is called.
class FreezeWatchdog {
  FreezeWatchdog._();
  static final FreezeWatchdog instance = FreezeWatchdog._();

  /// How often the heartbeat checks in.
  ///
  /// Also the floor on resolution: a freeze shorter than this may fall between
  /// ticks entirely. 100ms is a reasonable trade — frequent enough to catch a
  /// perceptible stall, rare enough to be nearly free.
  Duration heartbeatInterval = const Duration(milliseconds: 100);

  /// A gap beyond the interval by more than this is reported as a freeze.
  ///
  /// Not zero: timers are best-effort and routinely run a few milliseconds
  /// late, so a small threshold would report constant phantom freezes. 250ms is
  /// comfortably past "perceptible jank" and well short of "the app is broken".
  Duration freezeThreshold = const Duration(milliseconds: 250);

  /// A rendered frame slower than this is recorded as a slow frame.
  ///
  /// ~2 frames at 60Hz. One long frame is noise; a run of them is the jank you
  /// can feel.
  Duration slowFrameThreshold = const Duration(milliseconds: 32);

  /// Oldest events are dropped past these caps.
  int maxFreezes = 100;
  int maxSlowFrames = 500;

  final ListQueue<FreezeEvent> _freezes = ListQueue();
  final ListQueue<SlowFrameEvent> _slowFrames = ListQueue();

  /// Newest last, matching the timeline's left-to-right reading order.
  List<FreezeEvent> get freezes => List.unmodifiable(_freezes);
  List<SlowFrameEvent> get slowFrames => List.unmodifiable(_slowFrames);

  Timer? _heartbeat;
  DateTime? _lastBeat;
  TimingsCallback? _timingsCallback;

  bool get isRunning => _heartbeat != null;

  /// A "something changed" signal, coalesced so a burst of slow frames notifies
  /// once rather than per frame.
  final ValueNotifier<int> tick = ValueNotifier<int>(0);
  bool _notifyScheduled = false;

  /// Begins watching. Idempotent.
  ///
  /// Opt-in by design — see the class docs on cost. Does nothing when the kill
  /// switch is off, so a release build that calls this still pays nothing.
  void start() {
    if (_heartbeat != null || !DevtrayKillSwitch.enabled) return;

    _lastBeat = DateTime.now();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => _beat());

    // Frames that rendered but took too long. Complements the heartbeat rather
    // than replacing it: this sees slow frames, the heartbeat sees absent ones.
    _timingsCallback = _onTimings;
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback!);
  }

  void stop() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _lastBeat = null;

    if (_timingsCallback case final cb?) {
      SchedulerBinding.instance.removeTimingsCallback(cb);
      _timingsCallback = null;
    }
  }

  void clear() {
    _freezes.clear();
    _slowFrames.clear();
    _scheduleNotify();
  }

  /// Records a freeze directly.
  ///
  /// For tests, and for a host that detects stalls its own way — a watchdog
  /// isolate, a platform-side ANR signal — and wants them on the same lane.
  /// Real detection is retrospective and cannot be driven synchronously, which
  /// makes the buffer and rendering untestable without this.
  @visibleForTesting
  void recordFreezeForTesting(FreezeEvent event) {
    _push(_freezes, event, maxFreezes);
    _scheduleNotify();
  }

  /// The heartbeat.
  ///
  /// Measures elapsed wall-clock against the interval it asked for. The excess
  /// *is* the freeze: time the isolate owed this timer but spent elsewhere,
  /// blocked.
  void _beat() {
    final now = DateTime.now();
    final last = _lastBeat;
    _lastBeat = now;
    if (last == null) return;

    final freeze = freezeBetween(last: last, now: now, interval: heartbeatInterval, threshold: freezeThreshold);
    if (freeze == null) return;

    _push(_freezes, freeze, maxFreezes);
    _scheduleNotify();
  }

  /// The freeze implied by two consecutive heartbeats, or null if the gap is
  /// within tolerance.
  ///
  /// Pulled out as a pure function because the surrounding detection cannot be
  /// tested: it compares wall-clock time, which `fakeAsync` does not control,
  /// and genuinely blocking the isolate would block the test runner too. This
  /// is the part with arithmetic in it, so this is the part worth testing.
  ///
  /// The overshoot — elapsed time beyond what the timer asked for — *is* the
  /// freeze: time the isolate owed this timer but spent blocked elsewhere.
  static FreezeEvent? freezeBetween({
    required DateTime last,
    required DateTime now,
    required Duration interval,
    required Duration threshold,
  }) {
    final overshoot = now.difference(last) - interval;
    if (overshoot < threshold) return null;

    // Spans from when the tick was due to when it actually ran.
    return FreezeEvent(start: last.add(interval), end: now, duration: overshoot);
  }

  void _onTimings(List<FrameTiming> timings) {
    var recorded = false;

    for (final t in timings) {
      final build = t.buildDuration;
      final raster = t.rasterDuration;
      if (build + raster < slowFrameThreshold) continue;

      _push(
        _slowFrames,
        SlowFrameEvent(
          // FrameTiming carries monotonic-clock microseconds, which are not a
          // wall-clock instant. The timeline plots against wall clock, so this
          // stamps arrival — accurate to within a frame, which is finer than
          // anything the timeline draws.
          at: DateTime.now(),
          build: build,
          raster: raster,
        ),
        maxSlowFrames,
      );
      recorded = true;
    }

    if (recorded) _scheduleNotify();
  }

  static void _push<T>(ListQueue<T> queue, T value, int cap) {
    queue.addLast(value);
    while (queue.length > cap) {
      queue.removeFirst();
    }
  }

  /// Coalesced onto a microtask.
  ///
  /// `addTimingsCallback` runs inside the frame pipeline, so notifying inline
  /// would mark listening widgets dirty mid-frame — the same hazard
  /// `CoalescingValueNotifier` exists for on the log store.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      tick.value++;
    });
  }
}
