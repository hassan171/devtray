import 'package:flutter/material.dart';

import '../../core/debug_text_styles.dart';
import '../../core/devtray_theme.dart';
import '../../widgets/copyable_section.dart';
import '../devtray_nav.dart';

/// One route visit, for the Timeline's `nav` lane.
///
/// Unlike the other lanes there is no owning page to borrow a detail widget
/// from — routes have no page of their own — so this is it. It answers the
/// question the span raises: what was this, how long was it up, and is it
/// still.
class RouteDetailPane extends StatelessWidget {
  final RouteVisit visit;

  const RouteDetailPane({super.key, required this.visit});

  static String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  static String _duration(Duration d) {
    if (d.inSeconds < 1) return '${d.inMilliseconds}ms';
    if (d.inMinutes < 1) return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
    return '${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final duration = visit.duration;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: t.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  visit.isOverlay ? 'OVERLAY' : 'SCREEN',
                  style: DebugTextStyles.label(color: t.warning, fontSize: 9),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  visit.name,
                  overflow: TextOverflow.ellipsis,
                  style: DebugTextStyles.debugMono(color: t.text, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              if (visit.isCurrent)
                Text('current', style: TextStyle(fontSize: 10, color: t.success)),
            ],
          ),
          CopyableSection(
            title: 'Route',
            body: [
              'name: ${visit.name}',
              if (visit.from case final origin?)
                visit.wasReturn ? 'returned from: $origin' : 'came from: $origin'
              else
                'came from: (first route)',
              'type: ${visit.type}',
              if (visit.isOverlay) 'over: ${DevtrayNav.instance.currentScreen?.name ?? '(nothing)'}',
              'entered: ${_clock(visit.enteredAt)}',
              if (visit.leftAt case final left?) 'left: ${_clock(left)}',
              if (duration != null)
                'duration: ${_duration(duration)}'
              else
                // Not "duration: 0" — it has not ended, which is different from
                // having lasted no time.
                'duration: still open',
            ].join('\n'),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 13, color: t.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  visit.isOverlay
                      ? 'A dialog or sheet. It sits over a screen rather than being one, so it does '
                          'not change the `screen` field — entries captured while it was up still name '
                          'the page beneath.'
                      : 'Every log line and network request captured during this span carries '
                          '`screen: ${visit.name}`. Open one to see it on its Context tab.',
                  style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
