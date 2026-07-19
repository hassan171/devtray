import 'package:flutter/material.dart';

import '../core/devtray_theme.dart';
import 'timeline_event.dart';

/// Vertical layout of the lanes. Shared by the painter and the hit-tester, so
/// what you tap is what you see — the two cannot drift.
class TimelineMetrics {
  /// Height of one lane, including its padding.
  static const double laneHeight = 34;

  /// Height of the time-axis strip along the top.
  static const double axisHeight = 18;

  /// Thickness of a network bar.
  static const double barHeight = 12;

  /// Radius of an instant mark (log, state).
  static const double markRadius = 4;

  /// Width of the lane labels down the left edge.
  static const double gutter = 46;

  static const List<TimelineLane> lanes = TimelineLane.values;

  static double get totalHeight => axisHeight + lanes.length * laneHeight;

  /// Vertical centre of [lane]'s row.
  static double laneCenter(TimelineLane lane) => axisHeight + lanes.indexOf(lane) * laneHeight + laneHeight / 2;

  /// Maps a time to an x offset within the plot area.
  static double xFor(DateTime t, DateTime from, DateTime to, double width) {
    final span = to.difference(from).inMicroseconds;
    if (span <= 0) return gutter;
    final plot = width - gutter;
    final fraction = t.difference(from).inMicroseconds / span;
    return gutter + fraction.clamp(0.0, 1.0) * plot;
  }
}

/// Draws the lanes.
///
/// A [CustomPainter] rather than a widget per event, deliberately. A full
/// buffer is 500 requests plus 1000 log lines; laying that out as widgets is
/// the exact trap the Logs and Network lists had to be dug out of. One painter
/// draws the lot in a single pass, and nothing is built for events that are
/// off-window.
class TimelinePainter extends CustomPainter {
  final List<TimelineEvent> events;
  final DateTime from;
  final DateTime to;
  final DevtrayTheme theme;

  /// The event under the last tap, drawn with a highlight ring.
  final TimelineEvent? selected;

  TimelinePainter({
    required this.events,
    required this.from,
    required this.to,
    required this.theme,
    this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    for (final event in events) {
      final y = TimelineMetrics.laneCenter(event.lane);
      final x = TimelineMetrics.xFor(event.start, from, to, size.width);
      final isSelected = identical(event, selected);

      // Freezes have duration and draw as bars; slow frames are instants.
      if (event.lane == TimelineLane.network || event.hasDuration) {
        _paintBar(canvas, size, event, x, y, isSelected);
      } else {
        _paintMark(canvas, event, x, y, isSelected);
      }
    }
  }

  /// Lane separators, labels, and second ticks along the axis.
  void _paintGrid(Canvas canvas, Size size) {
    final line = Paint()
      ..color = theme.border.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    for (final lane in TimelineMetrics.lanes) {
      final y = TimelineMetrics.laneCenter(lane) + TimelineMetrics.laneHeight / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      _paintText(
        canvas,
        _laneLabel(lane),
        Offset(4, TimelineMetrics.laneCenter(lane) - 5),
        theme.textMuted,
        9,
      );
    }

    // Roughly ten gridlines, at a round interval for whatever scale we're at.
    // A fixed one-per-second breaks in both directions: unreadable at ten
    // minutes, and a single line (labelled "0s") once zoomed under a second,
    // which is exactly the range that makes this page worth having.
    final spanMicros = to.difference(from).inMicroseconds;
    if (spanMicros <= 0) return;

    final stepMicros = _niceStep(spanMicros ~/ 10);

    // Start at the first round multiple inside the window, so gridlines sit on
    // stable times and don't crawl as the window slides.
    final firstTick = (from.microsecondsSinceEpoch / stepMicros).ceil() * stepMicros;

    for (var us = firstTick; us <= to.microsecondsSinceEpoch; us += stepMicros) {
      final t = DateTime.fromMicrosecondsSinceEpoch(us);
      final x = TimelineMetrics.xFor(t, from, to, size.width);
      canvas.drawLine(
        Offset(x, TimelineMetrics.axisHeight),
        Offset(x, size.height),
        Paint()..color = theme.border.withValues(alpha: 0.14),
      );
      _paintText(canvas, _tickLabel(t, stepMicros), Offset(x + 2, 3), theme.textMuted, 8);
    }
  }

  /// Rounds a raw interval up to something a human reads easily — 1/2/5 × a
  /// power of ten, in microseconds.
  static int _niceStep(int rawMicros) {
    const candidates = [
      1000, 2000, 5000, // 1ms, 2ms, 5ms
      10000, 20000, 50000, // 10ms …
      100000, 200000, 500000,
      1000000, 2000000, 5000000, // 1s, 2s, 5s
      10000000, 15000000, 30000000,
      60000000, 120000000, 300000000, // 1m, 2m, 5m
    ];
    for (final c in candidates) {
      if (c >= rawMicros) return c;
    }
    return candidates.last;
  }

  /// Labels the tick at whatever precision the current zoom warrants.
  static String _tickLabel(DateTime t, int stepMicros) {
    if (stepMicros < 1000000) {
      // Sub-second: show the fraction, which is the only part that's changing.
      return '.${(t.millisecond ~/ 100)}${(t.millisecond % 100) ~/ 10}';
    }
    if (stepMicros < 60000000) return '${t.second}s';
    return '${t.minute}:${t.second.toString().padLeft(2, '0')}';
  }

  void _paintBar(Canvas canvas, Size size, TimelineEvent e, double x, double y, bool isSelected) {
    final endX = TimelineMetrics.xFor(e.effectiveEnd(to), from, to, size.width);
    // A floor, so a 2ms request is still visible and still tappable rather than
    // collapsing to a hairline.
    final width = (endX - x).clamp(3.0, size.width);

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y - TimelineMetrics.barHeight / 2, width, TimelineMetrics.barHeight),
      const Radius.circular(2),
    );

    final color = e.isError
        ? theme.error
        : e.isPending
        ? theme.textMuted
        : theme.accent;

    // A freeze is drawn solid: it's the one thing on this chart you want to
    // catch peripherally, without reading anything.
    final alpha = e.lane == TimelineLane.jank
        ? 0.9
        : e.isPending
        ? 0.35
        : 0.75;
    canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: alpha));

    if (isSelected) {
      canvas.drawRRect(
        rect,
        Paint()
          ..color = theme.text
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _paintMark(Canvas canvas, TimelineEvent e, double x, double y, bool isSelected) {
    final color = e.isError
        ? theme.error
        : e.lane == TimelineLane.state
        ? theme.success
        : e.lane == TimelineLane.jank
        ? theme.warning
        : theme.textMuted;

    if (e.lane == TimelineLane.state) {
      // A diamond, so state reads differently from logs at a glance without
      // relying on colour alone.
      final path = Path()
        ..moveTo(x, y - TimelineMetrics.markRadius - 1)
        ..lineTo(x + TimelineMetrics.markRadius + 1, y)
        ..lineTo(x, y + TimelineMetrics.markRadius + 1)
        ..lineTo(x - TimelineMetrics.markRadius - 1, y)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.85));
    } else {
      canvas.drawCircle(
        Offset(x, y),
        e.isError ? TimelineMetrics.markRadius + 1 : TimelineMetrics.markRadius,
        Paint()..color = color.withValues(alpha: e.isError ? 0.95 : 0.6),
      );
    }

    if (isSelected) {
      canvas.drawCircle(
        Offset(x, y),
        TimelineMetrics.markRadius + 3,
        Paint()
          ..color = theme.text
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _paintText(Canvas canvas, String text, Offset at, Color color, double size) {
    TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )
      ..layout()
      ..paint(canvas, at);
  }

  static String _laneLabel(TimelineLane lane) => switch (lane) {
    TimelineLane.jank => 'JANK',
    TimelineLane.network => 'NET',
    TimelineLane.log => 'LOG',
    TimelineLane.state => 'STATE',
  };

  @override
  bool shouldRepaint(TimelinePainter old) =>
      old.from != from || old.to != to || old.events.length != events.length || !identical(old.selected, selected) || old.theme != theme;
}

/// Finds the event under a tap.
///
/// Uses [TimelineMetrics] rather than its own geometry, so the hit target and
/// the drawn mark are the same thing by construction — the classic failure of a
/// hand-painted list is a tap that lands somewhere other than what you touched.
TimelineEvent? hitTestTimeline({
  required Offset position,
  required List<TimelineEvent> events,
  required DateTime from,
  required DateTime to,
  required double width,
}) {
  const slop = 8.0;
  TimelineEvent? best;
  var bestDistance = double.infinity;

  for (final e in events) {
    final y = TimelineMetrics.laneCenter(e.lane);
    if ((position.dy - y).abs() > TimelineMetrics.laneHeight / 2) continue;

    final x = TimelineMetrics.xFor(e.start, from, to, width);

    // Matches the painter's choice of bar vs mark, so the hit target is the
    // shape that was drawn.
    if (e.lane == TimelineLane.network || e.hasDuration) {
      final endX = TimelineMetrics.xFor(e.effectiveEnd(to), from, to, width);
      final right = x + (endX - x).clamp(3.0, width);
      // Inside the bar is an exact hit; near it falls back to distance so a
      // very short bar is still reachable.
      if (position.dx >= x - slop && position.dx <= right + slop) return e;
    }

    final distance = (position.dx - x).abs();
    if (distance <= slop && distance < bestDistance) {
      bestDistance = distance;
      best = e;
    }
  }

  return best;
}
