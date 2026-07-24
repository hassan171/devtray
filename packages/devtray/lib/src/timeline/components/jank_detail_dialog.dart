import 'package:flutter/material.dart';

import '../../core/debug_text_styles.dart';
import '../../core/devtray_theme.dart';
import '../devtray_jank.dart';
import '../timeline_event.dart';

/// What happened during a freeze or a slow frame.
///
/// A freeze has no stack trace — by the time the heartbeat can measure the gap,
/// whatever caused it has already returned (see [DevtrayJank]). So the
/// question this answers is not *what was running* but **what else was going on
/// at the time**: which requests were in flight, what got logged, what state
/// changed. That is circumstantial rather than conclusive, and the dialog says
/// so rather than implying a causal link it cannot prove.
class JankDetailDialog extends StatelessWidget {
  final TimelineEvent event;

  /// Everything the timeline was showing, filtered here to the freeze window.
  /// Passed in rather than re-collected so the dialog shows exactly what the
  /// lanes showed.
  final List<TimelineEvent> allEvents;

  const JankDetailDialog({super.key, required this.event, required this.allEvents});

  static Future<void> show(BuildContext context, TimelineEvent event, List<TimelineEvent> allEvents) {
    final theme = DevtrayTheme.of(context);

    return showDialog<void>(
      context: context,
      builder: (_) => DevtrayThemeScope(
        // A new route, outside the page's theme scope.
        theme: theme,
        child: JankDetailDialog(event: event, allEvents: allEvents),
      ),
    );
  }

  /// Events overlapping the freeze, excluding the jank lane itself.
  ///
  /// Widened slightly at the start: the work that caused a freeze usually
  /// *began* just before the isolate stopped responding, so a strict window
  /// would exclude the most likely culprit — the request that landed a moment
  /// earlier and was being decoded when everything stopped.
  List<TimelineEvent> get _during {
    const lead = Duration(milliseconds: 500);
    final from = event.start.subtract(lead);
    final to = event.effectiveEnd(event.start);

    return allEvents.where((e) {
      if (e.lane == TimelineLane.jank) return false;
      final end = e.effectiveEnd(to);
      return !end.isBefore(from) && !e.start.isAfter(to);
    }).toList()..sort((a, b) => a.start.compareTo(b.start));
  }

  bool get _isFreeze => event.source is FreezeEvent;

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final during = _during;

    return Dialog(
      backgroundColor: t.background,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(event: event, isFreeze: _isFreeze),
            Divider(color: t.border, height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Measurements(event: event, isFreeze: _isFreeze),
                    const SizedBox(height: 14),
                    _Concurrent(during: during, isFreeze: _isFreeze),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final TimelineEvent event;
  final bool isFreeze;

  const _Header({required this.event, required this.isFreeze});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final color = isFreeze ? t.error : t.warning;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      child: Row(
        children: [
          Icon(isFreeze ? Icons.ac_unit : Icons.slow_motion_video, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isFreeze ? 'UI freeze' : 'Slow frame',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(Icons.close, size: 16, color: t.textMuted),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Measurements extends StatelessWidget {
  final TimelineEvent event;
  final bool isFreeze;

  const _Measurements({required this.event, required this.isFreeze});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final source = event.source;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (source is FreezeEvent) ...[
          _Row(label: 'Blocked for', value: '${source.duration.inMilliseconds}ms', emphasis: true),
          _Row(label: 'From', value: _time(source.start)),
          _Row(label: 'Until', value: _time(source.end)),
        ] else if (source is SlowFrameEvent) ...[
          _Row(label: 'Total', value: '${source.total.inMilliseconds}ms', emphasis: true),
          // Build vs raster is the one genuinely diagnostic split available
          // here: a slow build points at widget work, a slow raster at painting
          // or shader compilation.
          _Row(label: 'Build', value: '${source.build.inMilliseconds}ms'),
          _Row(label: 'Raster', value: '${source.raster.inMilliseconds}ms'),
          _Row(label: 'At', value: _time(source.at)),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: t.border.withValues(alpha: 0.6)),
          ),
          child: Text(
            // Stated plainly, because the absence of a stack trace is the first
            // thing anyone will look for here.
            isFreeze
                ? 'No stack trace: a blocked isolate cannot record what blocked '
                      'it. The heartbeat only measures the gap once the isolate '
                      'starts responding again.'
                : 'This frame rendered, just late — unlike a freeze, where '
                      'nothing rendered at all.',
            style: TextStyle(fontSize: 10, color: t.textMuted, height: 1.4),
          ),
        ),
      ],
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';
}

/// What else the app was doing.
class _Concurrent extends StatelessWidget {
  final List<TimelineEvent> during;
  final bool isFreeze;

  const _Concurrent({required this.during, required this.isFreeze});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AROUND THIS TIME', style: DebugTextStyles.label(color: t.textMuted, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          // The honest framing. Correlation is all this can offer, and saying
          // so is better than a list that implies causation.
          'What else was happening. Circumstantial — nothing here is proven to '
          'be the cause.',
          style: TextStyle(fontSize: 10, color: t.textMuted, height: 1.35),
        ),
        const SizedBox(height: 8),
        if (during.isEmpty)
          Text(
            isFreeze
                ? 'Nothing else was captured in this window — the cause was '
                      'likely synchronous work the overlay does not observe.'
                : 'Nothing else was captured around this frame.',
            style: TextStyle(fontSize: 11, color: t.textMuted),
          )
        else
          for (final e in during) _ConcurrentRow(event: e),
      ],
    );
  }
}

class _ConcurrentRow extends StatelessWidget {
  final TimelineEvent event;

  const _ConcurrentRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final color = switch (event.lane) {
      TimelineLane.network => t.accent,
      TimelineLane.state => t.success,
      _ => t.textMuted,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              switch (event.lane) {
                TimelineLane.network => 'net',
                TimelineLane.log => 'log',
                TimelineLane.state => 'state',
                TimelineLane.route => 'nav',
                TimelineLane.jank => '',
              },
              style: DebugTextStyles.label(color: color, fontSize: 8),
            ),
          ),
          Expanded(
            child: Text(
              event.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DebugTextStyles.debugMono(
                color: event.isError ? t.error : t.text,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ),
          if (event.duration case final d?)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '${d.inMilliseconds}ms',
                style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasis;

  const _Row({required this.label, required this.value, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(fontSize: 11, color: t.textMuted)),
          ),
          Text(
            value,
            style: DebugTextStyles.debugMono(
              color: emphasis ? t.error : t.text,
              fontSize: emphasis ? 13 : 11,
              fontWeight: emphasis ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
