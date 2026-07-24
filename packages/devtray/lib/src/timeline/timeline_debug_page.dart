import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/debug_page.dart';
import '../core/debug_text_styles.dart';
import '../core/devtray_theme.dart';
import '../logs/components/log_detail_dialog.dart';
import '../logs/devtray_log.dart';
import '../nav/components/route_detail_pane.dart';
import '../nav/devtray_nav.dart';
import '../network/components/network_detail_pane.dart';
import '../network/html_previewer.dart';
import '../network/mocking/devtray_mocks.dart';
import '../network/devtray_net.dart';
import '../state/components/state_detail_pane.dart';
import '../state/devtray_state.dart';
import 'components/jank_detail_dialog.dart';
import 'devtray_jank.dart';
import 'timeline_event.dart';
import 'timeline_painter.dart';

/// Requests, logs and state changes on one shared time axis.
///
/// The question this page exists for is the one no other page can answer:
/// *"the screen went blank — what actually happened?"* Each other page holds a
/// third of the story and its own clock, so today you answer it by switching
/// tabs and comparing timestamps by eye. Here the request, the error it
/// produced and the state emission that followed sit above one another.
///
/// ## It owns no data
///
/// Every store already timestamps its entries, so this is a *view* over the
/// three existing singletons rather than a fourth store to keep in sync.
/// Nothing is captured on its behalf and there is no steady-state cost: it
/// reads what the other pages read, only while it is on screen.
///
/// ```dart
/// runDebugApp(pages: [TimelineDebugPage(), NetworkDebugPage(), LogsDebugPage()]);
/// ```
class TimelineDebugPage extends DebugPage {
  /// How much history the window shows.
  final Duration window;

  /// Renders an HTML response body in the request detail, exactly as
  /// [NetworkDebugPage.onPreviewHtml] does. Null hides the button.
  final DebugHtmlPreviewer? onPreviewHtml;

  /// Watch for UI freezes and slow frames, and draw them as a fourth lane.
  ///
  /// **Opt-in**, because it is the first thing in the overlay with a real
  /// steady-state cost: a periodic heartbeat plus a per-frame callback. Every
  /// other page is passive.
  ///
  /// Detection is retrospective and has real limits — a frozen isolate cannot
  /// report its own freeze while it is frozen. See [DevtrayJank].
  ///
  /// The watchdog runs only while this page is mounted, so the cost is paid
  /// while the panel is open and not otherwise. That also means a freeze while
  /// the overlay is closed goes unrecorded; call [DevtrayJank.instance.start]
  /// from your own bootstrap if you want it running for the whole session.
  final bool detectFreezes;

  const TimelineDebugPage({
    this.window = const Duration(seconds: 30),
    this.onPreviewHtml,
    this.detectFreezes = false,
  });

  @override
  String get title => 'Timeline';

  @override
  IconData? get icon => Icons.timeline;

  @override
  Widget build(BuildContext context) => _TimelineView(
    window: window,
    onPreviewHtml: onPreviewHtml,
    detectFreezes: detectFreezes,
  );
}

class _TimelineView extends StatefulWidget {
  final Duration window;
  final DebugHtmlPreviewer? onPreviewHtml;
  final bool detectFreezes;

  const _TimelineView({required this.window, this.onPreviewHtml, required this.detectFreezes});

  @override
  State<_TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<_TimelineView> {
  /// Redraws while following, so a pending request's bar grows and the window
  /// slides even when no store has ticked.
  ///
  /// Only runs while this page is mounted AND following — a paused timeline is
  /// a still image and costs nothing.
  Timer? _ticker;

  /// End of the visible window. Null means "now", i.e. following live.
  ///
  /// Frozen the moment you interact, because a timeline that keeps sliding
  /// while you are trying to read a 200ms span is unusable — the same reason
  /// the Logs and Network lists stop following when you scroll back.
  DateTime? _frozenAt;

  bool get _isLive => _frozenAt == null;

  /// How much time the window spans. Starts at the configured window and
  /// changes with pinch-zoom.
  ///
  /// Held in microseconds rather than a [Duration] because zooming multiplies
  /// it by a fractional scale, and integer division on a Duration would make
  /// small zoom steps round away to nothing.
  late double _spanMicros = widget.window.inMicroseconds.toDouble();

  Duration get _span => Duration(microseconds: _spanMicros.round());

  /// Bounds on the zoom range.
  ///
  /// The lower bound is what makes the page worth having: at 100ms you can see
  /// the order of things inside a single frame's worth of work. The upper bound
  /// stops a scroll-zoom from opening a window with nothing in it.
  ///
  /// Must not be above the smallest [_ZoomPresets.presets] entry, or that chip
  /// would clamp to something else and never show as active.
  static const double _minSpanMicros = 100 * 1000;
  static const double _maxSpanMicros = 10 * 60 * 1000 * 1000;

  /// Window end at the moment the drag began, so each move is measured from a
  /// fixed origin rather than accumulating rounding error frame by frame.
  DateTime? _dragAnchorEnd;

  TimelineEvent? _selected;

  /// Lane filters. Off-lanes are excluded from collection entirely rather than
  /// drawn and hidden, so a muted lane costs nothing.
  final Set<TimelineLane> _hidden = {};

  /// True when this page started the watchdog, so it only stops what it
  /// started — an app that runs the watchdog for the whole session must not
  /// have it switched off by closing the panel.
  bool _ownsWatchdog = false;

  @override
  void initState() {
    super.initState();
    _startTicker();

    if (widget.detectFreezes && !DevtrayJank.instance.isRunning) {
      _ownsWatchdog = true;
      DevtrayJank.instance.start();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_ownsWatchdog) DevtrayJank.instance.stop();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    // ~10fps. The timeline is a wide view of seconds; redrawing it at 60 would
    // spend frames to move a bar by a fraction of a pixel.
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _isLive) setState(() {});
    });
  }

  void _freeze() {
    if (!_isLive) return;
    setState(() => _frozenAt = DateTime.now());
    _ticker?.cancel();
  }

  /// Resumes following. **Keeps the current zoom.**
  ///
  /// This used to reset the span, on the theory that zoom belonged to the
  /// investigation rather than the live view. That was wrong: the ordinary
  /// workflow is to pick a scale, pause to read something, then resume watching
  /// *at that scale* — so resetting made the live/paused toggle hostile to the
  /// thing it exists for. The reset button is the way back to the default, and
  /// it is explicit.
  void _resume() {
    setState(() {
      _frozenAt = null;
      _selected = null;
    });
    _startTicker();
  }

  /// Where the pointer went down, to tell a tap from a drag on pointer-up.
  Offset? _pointerDownAt;

  /// True once the pointer has moved far enough to be a pan rather than a tap.
  bool _isDragging = false;

  /// Movement beyond which a press becomes a drag. Matches Flutter's own
  /// `kTouchSlop` in spirit — below it, a wobbly finger should still tap.
  static const double _dragSlop = 6;

  void _onPointerDown(PointerDownEvent event, double width) {
    _pointerDownAt = event.localPosition;
    _isDragging = false;
    _dragAnchorEnd = _frozenAt ?? DateTime.now();
  }

  void _onPointerMove(PointerMoveEvent event, double width) {
    final downAt = _pointerDownAt;
    final anchorEnd = _dragAnchorEnd;
    if (downAt == null || anchorEnd == null || width <= 0) return;

    final dx = event.localPosition.dx - downAt.dx;
    if (!_isDragging && dx.abs() < _dragSlop) return;

    if (!_isDragging) {
      _isDragging = true;
      // Freeze on the first real movement, not on touch-down: a tap should
      // select without silently pausing the page.
      _freeze();
      // Capture the window end ONCE, here. It used to be re-read from
      // `_frozenAt` on every move — which `_panBy` had just written — so each
      // move measured its delta from where the previous one landed while `dx`
      // was still measured from touch-down. The two cancelled and the window
      // never moved at all.
      _dragAnchorEnd = _frozenAt;
    }

    _panBy(dx, width, anchorEnd: _dragAnchorEnd ?? anchorEnd);
  }

  void _onPointerUp(PointerUpEvent event, List<TimelineEvent> events, DateTime from, DateTime to, double width) {
    final wasDrag = _isDragging;
    _endDrag();
    if (wasDrag) return;

    // A press that never became a drag is a tap — reconstructed by hand,
    // because a raw Listener has no notion of one.
    _handleTap(event.localPosition, events, from, to, width);
  }

  void _endDrag() {
    _pointerDownAt = null;
    _dragAnchorEnd = null;

    _isDragging = false;
  }

  /// Trackpad / mouse wheel. Horizontal scroll pans; ctrl+wheel zooms.
  void _onPointerSignal(PointerSignalEvent event, double width) {
    if (event is! PointerScrollEvent) return;

    _freeze();

    // Vertical wheel with no horizontal component still pans — on a mouse
    // that's the only wheel there is, and a timeline has nothing to scroll
    // vertically.
    final dx = event.scrollDelta.dx.abs() > 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
    // A wheel notch is discrete — each event is its own gesture, so the
    // current window end IS the anchor.
    _panBy(-dx, width, anchorEnd: _frozenAt ?? DateTime.now());
  }

  /// Moves the window by [dx] pixels' worth of time, relative to [anchorEnd].
  ///
  /// Positive dx = drag right = go back in time, so the content follows the
  /// finger the way every other scrollable does.
  void _panBy(double dx, double width, {required DateTime anchorEnd}) {
    final plotWidth = width - TimelineMetrics.gutter;
    final microsPerPixel = _spanMicros / (plotWidth <= 0 ? 1 : plotWidth);
    final shift = (dx * microsPerPixel).round();

    // [anchorEnd] is the window end the gesture started from, so a drag is
    // always measured against a fixed origin rather than against its own
    // previous frame.
    setState(() => _frozenAt = anchorEnd.subtract(Duration(microseconds: shift)));
  }

  /// Sets the window span, from a zoom preset.
  ///
  /// Direct, since the presets are already the spans. The slider this replaced
  /// needed a logarithmic 0..1 mapping in both directions to keep the
  /// sub-second end reachable; the chips make that machinery unnecessary.
  ///
  /// Zooming does **not** pause. Narrowing the window while following is a
  /// perfectly reasonable thing to want — watching the last second of traffic
  /// as it arrives — and forcing a pause would make the live view unusable at
  /// close range.
  void _setSpan(Duration span) {
    setState(() => _spanMicros = span.inMicroseconds.toDouble().clamp(_minSpanMicros, _maxSpanMicros));
  }

  /// Back to the default zoom, still frozen.
  void _resetZoom() => setState(() => _spanMicros = widget.window.inMicroseconds.toDouble());


  void _handleTap(Offset position, List<TimelineEvent> events, DateTime from, DateTime to, double width) {
    final hit = hitTestTimeline(
      position: position,
      events: events,
      from: from,
      to: to,
      width: width,
    );

    // Tapping empty space freezes without selecting — that alone is useful when
    // something interesting just scrolled past.
    _freeze();
    setState(() => _selected = hit);
    if (hit != null) _openDetail(hit, events);
  }

  /// Opens the owning page's own detail widget in a sheet.
  ///
  /// Reusing them rather than rendering a reduced copy: they are already
  /// standalone widgets over an entry, and a second renderer would drift from
  /// the real one. It also sidesteps cross-page navigation, which the overlay
  /// has no mechanism for — the tab controller is private and pages have no
  /// identity, so "jump to the Network tab" is not currently expressible.
  /// Opens the owning page's own detail widget, in a dialog.
  ///
  /// A dialog for every lane, not a sheet for some and a dialog for others.
  /// Logs already had [LogDetailDialog]; wrapping the network and state panes
  /// the same way costs nothing and means one tap gesture has one result. The
  /// earlier mix came from reusing each page's existing presentation without
  /// noticing they disagreed.
  ///
  /// Reusing the panes rather than rendering a reduced copy: they are already
  /// standalone widgets over an entry, and a second renderer would drift from
  /// the real one. It also sidesteps cross-page navigation, which the overlay
  /// has no mechanism for — the tab controller is private and pages have no
  /// identity, so "jump to the Network tab" is not currently expressible.
  void _openDetail(TimelineEvent event, List<TimelineEvent> allEvents) {
    // Jank has no owning page, so it gets a dialog of its own — the measurement
    // plus what else was happening at the time. That correlation is the only
    // attribution available: a blocked isolate cannot record what blocked it,
    // so the other lanes are the evidence.
    if (event.lane == TimelineLane.jank) {
      JankDetailDialog.show(context, event, allEvents);
      return;
    }

    // Logs bring their own dialog, already shaped exactly like the one below.
    if (event.source case final LogEntry e) {
      LogDetailDialog.show(context, e);
      return;
    }

    final theme = DevtrayTheme.of(context);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => DevtrayThemeScope(
        // The dialog is a new route, outside this page's theme scope.
        theme: theme,
        child: Dialog(
          backgroundColor: theme.background,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: ConstrainedBox(
            // Bounded, because the panes are scrollable and would otherwise
            // take whatever height their content asked for.
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: timelineDetailFor(
                event.source,
                onBack: () => Navigator.of(dialogContext).pop(),
                onRefresh: () => setState(() {}),
                enableMocking: !DevtrayMocks.instance.isDisabled,
                onPreviewHtml: widget.onPreviewHtml,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    // Rebuilds when any store changes, so the timeline updates on the same
    // signal the owning pages use.
    return _MultiStoreListener(
      builder: (context) {
        final to = _frozenAt ?? DateTime.now();
        final from = to.subtract(_span);

        final events = collectTimelineEvents(
          from: from,
          to: to,
          includeNetwork: !_hidden.contains(TimelineLane.network),
          includeLogs: !_hidden.contains(TimelineLane.log),
          includeState: !_hidden.contains(TimelineLane.state),
          includeJank: !_hidden.contains(TimelineLane.jank),
          includeRoutes: !_hidden.contains(TimelineLane.route),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Toolbar(
              isLive: _isLive,
              eventCount: events.length,
              window: _span,
              isZoomed: _spanMicros != widget.window.inMicroseconds.toDouble(),
              onResetZoom: _resetZoom,
              hidden: _hidden,
              onToggleLane: (lane) => setState(() {
                _hidden.contains(lane) ? _hidden.remove(lane) : _hidden.add(lane);
              }),
              onResume: _resume,
              onPause: _freeze,
            ),
            const SizedBox(height: 6),
            // Sized to its content, not Expanded.
            //
            // Expanded made the box taller than the lanes it draws, so the
            // painted strip sat at the top of a much larger gesture area — and
            // a drag in the empty space below did nothing, which reads as "the
            // timeline doesn't scroll".
            SizedBox(
              height: TimelineMetrics.totalHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: t.border.withValues(alpha: 0.6)),
                ),
                child: LayoutBuilder(
                  // A raw Listener, not a GestureDetector.
                  //
                  // The scale recognizer has to win a gesture arena to fire,
                  // and it loses to plenty of things — including, on some
                  // platforms, whatever the panel around it is doing. That
                  // failure is invisible: the callbacks simply never run, and
                  // the page looks like it has no gestures at all, which is
                  // exactly how it was reported. Twice.
                  //
                  // Pointer events are delivered before arena resolution, so
                  // this cannot be outcompeted. The trade is doing the drag
                  // bookkeeping by hand, which for a single-axis pan is a few
                  // lines — and tap has to be reconstructed from down/up,
                  // below.
                  builder: (context, constraints) => Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) => _onPointerDown(e, constraints.maxWidth),
                    onPointerMove: (e) => _onPointerMove(e, constraints.maxWidth),
                    onPointerUp: (e) => _onPointerUp(e, events, from, to, constraints.maxWidth),
                    onPointerCancel: (_) => _endDrag(),
                    // Trackpad and mouse wheel: horizontal scroll pans, and
                    // ctrl+wheel zooms, matching what every timeline UI does.
                    onPointerSignal: (e) => _onPointerSignal(e, constraints.maxWidth),
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, TimelineMetrics.totalHeight),
                      painter: TimelinePainter(
                        events: events,
                        from: from,
                        to: to,
                        theme: t,
                        selected: _selected,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Visible controls, because the gestures are invisible: a painted
            // surface has no scrollbar and no handle, so "drag to pan" is
            // discoverable only by being told. These are also the only usable
            // route on a desktop or emulator, where pinch isn't available.
            _ZoomPresets(span: _span, onSelect: _setSpan),
            if (events.isEmpty) _EmptyHint(isLive: _isLive),
            const Spacer(),
            _Hint(isLive: _isLive),
          ],
        );
      },
    );
  }
}

/// Rebuilds its child when any of the three stores changes.
///
/// Nested builders rather than a merged listenable: each store already exposes
/// a coalesced tick, and nesting three of them is less machinery than a
/// Listenable.merge that would need disposing.
class _MultiStoreListener extends StatelessWidget {
  final WidgetBuilder builder;

  const _MultiStoreListener({required this.builder});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: DevtrayNet.instance.tick,
      builder: (context, _, _) => ValueListenableBuilder<int>(
        valueListenable: DevtrayLog.instance.tick,
        builder: (context, _, _) => ValueListenableBuilder<int>(
          valueListenable: DevtrayState.instance.tick,
          builder: (context, _, _) => ValueListenableBuilder<int>(
            valueListenable: DevtrayJank.instance.tick,
            builder: (context, _, _) => ValueListenableBuilder<int>(
              valueListenable: DevtrayNav.instance.tick,
              builder: (context, _, _) => builder(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final bool isLive;
  final int eventCount;
  final Duration window;
  final bool isZoomed;
  final VoidCallback onResetZoom;
  final Set<TimelineLane> hidden;
  final ValueChanged<TimelineLane> onToggleLane;
  final VoidCallback onResume;
  final VoidCallback onPause;

  const _Toolbar({
    required this.isLive,
    required this.eventCount,
    required this.window,
    required this.isZoomed,
    required this.onResetZoom,
    required this.hidden,
    required this.onToggleLane,
    required this.onResume,
    required this.onPause,
  });

  /// The window span, in whatever unit reads best at that scale — "800ms" is
  /// more useful than "0s", which is what a seconds-only readout shows once
  /// you have zoomed in far enough for the page to earn its keep.
  /// Drops a trailing `.0`, so a whole number reads as `10m` rather than
  /// `10.0m` — and so this readout matches the zoom chip labels exactly. Two
  /// spellings of the same span in one toolbar looks like two different values.
  String get _spanLabel {
    final ms = window.inMilliseconds;
    if (ms < 1000) return '${ms}ms';
    if (ms < 60000) return '${_trim(ms / 1000)}s';
    return '${_trim(ms / 60000)}m';
  }

  static String _trim(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Row(
      children: [
        // The live/paused state is the most important thing on this page:
        // reading a paused timeline as though it were live is the same failure
        // the Logs session banner guards against.
        InkWell(
          onTap: isLive ? onPause : onResume,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isLive ? t.error : t.accent).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (isLive ? t.error : t.accent).withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isLive ? Icons.circle : Icons.pause, size: 9, color: isLive ? t.error : t.accent),
                const SizedBox(width: 5),
                Text(
                  isLive ? 'LIVE' : 'PAUSED',
                  style: DebugTextStyles.label(color: isLive ? t.error : t.accent, fontSize: 9),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        for (final lane in TimelineLane.values) ...[
          _LaneChip(lane: lane, muted: hidden.contains(lane), onTap: () => onToggleLane(lane)),
          const SizedBox(width: 4),
        ],
        const Spacer(),
        // Only while zoomed — a control that is always there but usually a
        // no-op is noise on a toolbar this narrow.
        if (isZoomed) ...[
          InkWell(
            onTap: onResetZoom,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_out_map, size: 11, color: t.textMuted),
                  const SizedBox(width: 3),
                  Text('reset', style: TextStyle(fontSize: 9, color: t.textMuted)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          '$eventCount in $_spanLabel',
          style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}

class _LaneChip extends StatelessWidget {
  final TimelineLane lane;
  final bool muted;
  final VoidCallback onTap;

  const _LaneChip({required this.lane, required this.muted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final color = switch (lane) {
      TimelineLane.jank => t.error,
      TimelineLane.route => t.warning,
      TimelineLane.network => t.accent,
      TimelineLane.log => t.textMuted,
      TimelineLane.state => t.success,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: muted ? Colors.transparent : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: muted ? t.border : color.withValues(alpha: 0.55)),
        ),
        child: Text(
          switch (lane) {
            TimelineLane.jank => 'jank',
            TimelineLane.route => 'nav',
            TimelineLane.network => 'net',
            TimelineLane.log => 'log',
            TimelineLane.state => 'state',
          },
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: muted ? t.textMuted : color),
        ),
      ),
    );
  }
}

/// Zoom, as a slider.
///
/// Logarithmic: the useful range is 200ms to 10 minutes — three orders of
/// magnitude — and a linear slider would spend almost all its travel above a
/// minute, making the sub-second end unreachable in practice.
/// Zoom, as preset spans.
///
/// Chips rather than a slider. A Material `Slider` is a consumer-sized control
/// — a big round thumb, a wide press overlay, generous padding — and it looked
/// out of place on a panel where everything else is 9–11px mono and thin
/// bordered chips. It also spent a whole row on a control with maybe five
/// positions anyone actually wants, and hitting a specific span by dragging a
/// continuous log scale is fiddly.
///
/// These match [_LaneChip] deliberately, so the toolbar reads as one family of
/// controls rather than three unrelated widgets.
class _ZoomPresets extends StatelessWidget {
  /// The current span, for deciding which chip is active.
  final Duration span;

  final ValueChanged<Duration> onSelect;

  const _ZoomPresets({required this.span, required this.onSelect});

  /// Round spans across the useful range.
  ///
  /// Not evenly spaced — each is roughly 2–3× the last, because zoom gets used
  /// by jumping between orders of magnitude rather than nudging between
  /// adjacent seconds. The ends are what matter: 100ms is inside a single
  /// frame's work, where you can see the *order* things happened in; 10m is the
  /// whole session.
  ///
  /// A wider set than the six this started with, because 5×-apart presets left
  /// real gaps — nothing between 5s and 30s is a poor answer when the thing you
  /// are looking at took eight seconds.
  static const List<(String, Duration)> presets = [
    ('100ms', Duration(milliseconds: 100)),
    ('250ms', Duration(milliseconds: 250)),
    ('500ms', Duration(milliseconds: 500)),
    ('1s', Duration(seconds: 1)),
    ('2s', Duration(seconds: 2)),
    ('5s', Duration(seconds: 5)),
    ('10s', Duration(seconds: 10)),
    ('30s', Duration(seconds: 30)),
    ('1m', Duration(minutes: 1)),
    ('2m', Duration(minutes: 2)),
    ('5m', Duration(minutes: 5)),
    ('10m', Duration(minutes: 10)),
  ];

  /// The preset nearest the current span.
  ///
  /// Nearest rather than exact, because the span can land between presets —
  /// [TimelineDebugPage.window] is configurable, and a scroll-wheel zoom moves
  /// continuously. Leaving nothing highlighted in that case would read as
  /// broken.
  Duration get _active {
    var best = presets.first.$2;
    var bestGap = double.infinity;

    for (final (_, d) in presets) {
      // Compared on a log scale, so "nearest" means nearest in *ratio*. On a
      // linear scale 10m would swallow everything below it.
      final gap = (math.log(d.inMicroseconds) - math.log(span.inMicroseconds)).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = d;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final active = _active;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text('zoom', style: DebugTextStyles.label(color: t.textMuted, fontSize: 9)),
          const SizedBox(width: 6),
          // Scrolls, because twelve chips do not fit a phone-width panel and
          // wrapping them onto a second row would push the lanes down every
          // time the panel narrowed.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (label, duration) in presets) ...[
                    _ZoomChip(
                      label: label,
                      isActive: duration == active,
                      onTap: () => onSelect(duration),
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ZoomChip({required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isActive ? t.accent.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? t.accent.withValues(alpha: 0.55) : t.border),
        ),
        child: Text(
          label,
          style: DebugTextStyles.debugMono(
            color: isActive ? t.accent : t.textMuted,
            fontSize: 9,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Says what the gestures are.
///
/// Pan and pinch on a painted surface are invisible affordances — there is no
/// scrollbar and no handle, so without this the page looks static. Reported as
/// exactly that: "it's not scrolling".
class _Hint extends StatelessWidget {
  final bool isLive;

  const _Hint({required this.isLive});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Text(
        isLive ? 'Drag the lanes or use ‹ › to scroll back · tap a mark for detail' : 'Drag or ‹ › to scroll · slider to zoom · Live to resume',
        style: TextStyle(fontSize: 9, color: t.textMuted.withValues(alpha: 0.8)),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final bool isLive;

  const _EmptyHint({required this.isLive});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        isLive ? 'Nothing in this window yet — make a request, or log something.' : 'Nothing in this window. Resume to follow live.',
        style: TextStyle(fontSize: 11, color: t.textMuted),
      ),
    );
  }
}

/// The detail widget for a tapped timeline event's source.
///
/// A function rather than a switch buried in a dialog builder so it can be
/// tested. The route lane shipped without its case here, and the only symptom
/// was a dialog containing nothing — the fall-through was silent, and no test
/// could reach the switch to catch it.
@visibleForTesting
Widget timelineDetailFor(
  Object? source, {
  required VoidCallback onBack,
  required VoidCallback onRefresh,
  bool enableMocking = true,
  DebugHtmlPreviewer? onPreviewHtml,
}) {
  return switch (source) {
    final NetworkLogEntry e => NetworkDetailPane(
      entry: e,
      enableMocking: enableMocking,
      onPreviewHtml: onPreviewHtml,
      // The panes render a back arrow for their master/detail layout; here it
      // closes the dialog, which is the same "leave this detail" intent.
      onBack: onBack,
    ),
    final TrackedSource s => StateDetailPane(source: s, onBack: onBack, onRefresh: onRefresh),
    // Routes have no owning page to borrow a detail widget from, so the nav
    // lane brings its own.
    final RouteVisit v => RouteDetailPane(visit: v),
    // Never reached — every lane's source type is handled above. It was a
    // `SizedBox.shrink()`, which is why adding a lane without its detail
    // produced an empty dialog rather than an obvious failure.
    final other => Text('No detail view for ${other.runtimeType}'),
  };
}
