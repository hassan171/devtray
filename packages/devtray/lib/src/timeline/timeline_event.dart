import '../logs/log_store.dart';
import '../network/network_log_store.dart';
import '../state/state_inspector.dart';
import 'freeze_watchdog.dart';

/// Which lane an event is drawn in.
enum TimelineLane {
  /// UI freezes and slow frames. First, because it is the lane you scan for —
  /// the others explain what it shows.
  jank,

  /// Requests. Events here have duration.
  network,

  /// Log lines and reported errors.
  log,

  /// State emissions.
  state,
}

/// One thing that happened, placed on the shared time axis.
///
/// The timeline owns no data. Every store already timestamps its entries —
/// [NetworkLogEntry.startedAt] / [NetworkLogEntry.completedAt],
/// [LogEntry.time], [StateChangeEntry.time] — so this is a *view* over the
/// three existing stores rather than a fourth store to keep in sync. Nothing is
/// captured for the timeline's benefit; it reads what the other pages read.
///
/// The [source] object is carried through so tapping a mark can open the very
/// same detail widget the owning page would show, rather than a reduced copy
/// that would drift from it.
class TimelineEvent {
  final TimelineLane lane;

  /// When it happened. For a request, when it was sent.
  final DateTime start;

  /// When it finished, for events that have duration. Null for instants (a log
  /// line, a state emission) and for a request still in flight — the two cases
  /// are distinguished by [isPending].
  final DateTime? end;

  /// One line, shown on hover/tap and in the summary band.
  final String label;

  /// Draws in the error colour and gets a distinct mark: a failed request, an
  /// error-level log line.
  final bool isError;

  /// A request that hasn't completed. Drawn open-ended — it has a start but its
  /// bar has no right edge yet, which is exactly what "still waiting" looks
  /// like.
  final bool isPending;

  /// The originating [NetworkLogEntry], [LogEntry] or [TrackedSource].
  final Object source;

  const TimelineEvent({
    required this.lane,
    required this.start,
    required this.label,
    required this.source,
    this.end,
    this.isError = false,
    this.isPending = false,
  });

  /// True when this event occupies a span rather than an instant.
  bool get hasDuration => end != null && end!.isAfter(start);

  Duration? get duration => end?.difference(start);

  /// Where this event ends for layout purposes.
  ///
  /// A pending request is treated as running up to [now] so its bar grows as
  /// you watch it, rather than being invisible until it completes.
  ///
  /// Never returns a time before [start]: a request begun a moment after the
  /// window's end — or a [now] captured before it — would otherwise produce a
  /// negative-width bar.
  DateTime effectiveEnd(DateTime now) {
    if (end != null) return end!;
    if (!isPending) return start;
    return now.isAfter(start) ? now : start;
  }
}

/// Reads the three stores and returns everything inside a window, newest first.
///
/// Deliberately a plain function over the singletons rather than a class: there
/// is no state to keep. The page calls it on each rebuild, which happens when
/// one of the stores ticks — the same trigger the owning pages use.
///
/// [from] and [to] bound the window. An event is included when it *overlaps*
/// the window, not merely when it starts inside it, so a long request that
/// began before the window still draws its tail.
List<TimelineEvent> collectTimelineEvents({
  required DateTime from,
  required DateTime to,
  bool includeNetwork = true,
  bool includeLogs = true,
  bool includeState = true,
  bool includeJank = true,
}) {
  final events = <TimelineEvent>[];

  if (includeJank) {
    for (final f in FreezeWatchdog.instance.freezes) {
      if (f.end.isBefore(from) || f.start.isAfter(to)) continue;
      events.add(
        TimelineEvent(
          lane: TimelineLane.jank,
          start: f.start,
          end: f.end,
          // Always an error: a freeze past the threshold is never fine.
          isError: true,
          label: 'UI froze for ${f.duration.inMilliseconds}ms',
          source: f,
        ),
      );
    }

    for (final f in FreezeWatchdog.instance.slowFrames) {
      if (f.at.isBefore(from) || f.at.isAfter(to)) continue;
      events.add(
        TimelineEvent(
          lane: TimelineLane.jank,
          start: f.at,
          // An instant, not a span: FrameTiming's monotonic clock can't be
          // placed on the wall clock precisely enough to draw a bar honestly.
          label: 'Slow frame ${f.total.inMilliseconds}ms '
              '(build ${f.build.inMilliseconds}, raster ${f.raster.inMilliseconds})',
          source: f,
        ),
      );
    }
  }

  if (includeNetwork) {
    for (final e in NetworkLogStore.instance.entries) {
      final pending = e.status == NetworkLogStatus.pending;
      final end = e.completedAt ?? (pending ? to : e.startedAt);
      // Overlap, not containment: a request that started before the window but
      // is still running belongs on screen.
      if (end.isBefore(from) || e.startedAt.isAfter(to)) continue;

      events.add(
        TimelineEvent(
          lane: TimelineLane.network,
          start: e.startedAt,
          end: e.completedAt,
          isPending: pending,
          isError: e.status == NetworkLogStatus.failed,
          label: '${e.method} ${e.uri.path.isEmpty ? e.uri.host : e.uri.path}'
              '${e.statusCode == null ? '' : ' · ${e.statusCode}'}',
          source: e,
        ),
      );
    }
  }

  if (includeLogs) {
    for (final e in LogStore.instance.entries) {
      if (e.time.isBefore(from) || e.time.isAfter(to)) continue;
      events.add(
        TimelineEvent(
          lane: TimelineLane.log,
          start: e.time,
          isError: e.isError || e.level == LogLevel.error,
          label: e.title,
          source: e,
        ),
      );
    }
  }

  if (includeState) {
    for (final source in StateInspector.instance.sources) {
      for (final change in source.changes) {
        if (change.time.isBefore(from) || change.time.isAfter(to)) continue;
        events.add(
          TimelineEvent(
            lane: TimelineLane.state,
            start: change.time,
            // The source rather than the change: tapping opens StateDetailPane,
            // which renders a source and its whole history.
            source: source,
            label: source.type,
          ),
        );
      }
    }
  }

  return events;
}
