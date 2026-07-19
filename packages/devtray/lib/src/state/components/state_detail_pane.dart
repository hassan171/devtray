import 'package:flutter/material.dart';

import '../../core/devtray_theme.dart';
import '../../core/debug_text_styles.dart';
import '../../widgets/copyable_section.dart';
import '../devtray_state.dart';
import 'state_row.dart';

/// One source in full: its live state, any error, and every change it has
/// made — newest first.
///
/// The pane is ordered by **what you came for**: the live state first, the
/// fields it holds outside that state next, then the history that produced it.
/// The history is the story — it's shown, not hidden behind a chevron, because
/// "what changed just before it broke" is the question this page exists to
/// answer.
class StateDetailPane extends StatefulWidget {
  final TrackedSource source;
  final VoidCallback onBack;

  /// Re-reads the source's non-state fields. They change without a state emit,
  /// and the page only rebuilds on emits — so this is the only way to see them
  /// update.
  final VoidCallback onRefresh;

  const StateDetailPane({
    super.key,
    required this.source,
    required this.onBack,
    required this.onRefresh,
  });

  @override
  State<StateDetailPane> createState() => _StateDetailPaneState();
}

class _StateDetailPaneState extends State<StateDetailPane> {
  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final source = widget.source;
    final accent = sourceColor(context, source);

    // Read on every build, so the values are live rather than a snapshot from
    // whenever the source last emitted.
    final fields = DevtrayState.instance.liveFieldsOf(source);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header. The source's condition is carried by a colour bar under the
        // title rather than a word floating at the right edge — same trick as
        // the row's spine, so the two pages read alike.
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back, size: 18, color: t.text),
              onPressed: widget.onBack,
            ),
            Expanded(
              child: Text(
                source.type,
                overflow: TextOverflow.ellipsis,
                style: DebugTextStyles.debugMono(color: t.text, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            if (source.isClosed) ...[
              StateTag(label: 'closed', color: t.textMuted, icon: Icons.block_rounded),
              const SizedBox(width: 4),
            ],
            if (source.error != null) ...[
              StateTag(label: 'error', color: t.error, icon: Icons.priority_high_rounded),
              const SizedBox(width: 4),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(height: 2, color: accent.withValues(alpha: 0.5)),
        Expanded(
          // A CustomScrollView, not a ListView, so the change history can be a
          // lazy sliver. As a plain `children:` list every one of the (up to
          // 100) tiles was built on open, and each renders two values through
          // `display()` — up to 200 formatter calls, some of them full JSON
          // encodes, before the pane could show anything.
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(top: 12),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    CopyableSection(
                      title: 'Current state',
                      body: DevtrayState.instance.display(source.state, sourceType: source.type),
                    ),

                    // The error, if any, sits directly under the state — you
                    // want the failure next to the value that caused it, not
                    // below the history.
                    if (source.error != null) ...[
                      const SizedBox(height: 12),
                      CopyableSection(
                        title: 'Error',
                        titleColor: t.error,
                        body: '${source.error}\n\n${source.stackTrace ?? ''}',
                      ),
                    ],

                    // Fields the source holds OUTSIDE its state — a sync queue,
                    // a lookup map, a retry counter. Read live from the instance
                    // on every rebuild, so they're current. See
                    // DevtrayState.inspect.
                    if (fields.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _SectionHeader(
                        title: 'Fields',
                        // These change WITHOUT an emit — a queue gets pushed, a
                        // counter ticks — and the page only rebuilds on emits.
                        // So there has to be a way to re-read them.
                        action: IconButton(
                          tooltip: 'Re-read fields',
                          padding: EdgeInsets.zero,
                          // 44px hit area on a 14px glyph — the icon is small
                          // because it's secondary, but the target can't be.
                          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                          icon: Icon(Icons.refresh, size: 14, color: t.textMuted),
                          onPressed: widget.onRefresh,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _FieldTable(fields: fields),
                    ],

                    const SizedBox(height: 12),
                    _SectionHeader(
                      title: 'Changes',
                      trailing: Text(
                        '${source.changes.length}',
                        style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (source.changes.isEmpty)
                      // An empty state that says what to do, not just that
                      // there's nothing here.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        decoration: BoxDecoration(
                          color: t.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: t.border.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          'No changes yet — this source is still on its initial state.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.4),
                        ),
                      ),
                  ]),
                ),
              ),

              // The history, built lazily — only the tiles actually on screen
              // pay for their `display()` calls.
              SliverList.builder(
                itemCount: source.changes.length,
                itemBuilder: (context, i) => _ChangeTile(
                  key: ValueKey(source.changes[i].id),
                  change: source.changes[i],
                  formatTime: _formatTime,
                  sourceType: source.type,
                  // Newest first — mark it, so "what just happened" is findable
                  // without reading timestamps.
                  isLatest: i == 0,
                  // The last tile shouldn't draw a rail into empty space.
                  isLast: i == source.changes.length - 1,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Section title, optionally with an action or a count. One component so every
/// section on the pane sits on the same baseline.
class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.action, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    return Row(
      children: [
        Text(title, style: DebugTextStyles.label(color: t.textMuted, fontSize: 10)),
        const SizedBox(width: 6),
        Expanded(child: Container(height: 1, color: t.border.withValues(alpha: 0.6))),
        if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ?action,
      ],
    );
  }
}

/// The source's non-state fields as a two-column table.
class _FieldTable extends StatelessWidget {
  final Map<String, Object?> fields;
  const _FieldTable({required this.fields});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          for (final e in fields.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A max, not a fixed width — a long field name should get its
                  // space back from the value rather than overflow.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      e.key,
                      style: TextStyle(fontSize: 11, color: t.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      e.value?.toString() ?? 'null',
                      style: DebugTextStyles.debugMono(color: t.text, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One change: when, what triggered it, and the before/after pair.
///
/// Laid out as a **timeline** — a dot on a rail down the left — because the
/// history is a sequence, and a stack of identical cards doesn't say that. The
/// from/to pair uses `−`/`+` gutters and colour, so a diff reads as a diff.
class _ChangeTile extends StatelessWidget {
  final StateChangeEntry change;
  final String Function(DateTime) formatTime;
  final String sourceType;
  final bool isLatest;
  final bool isLast;

  const _ChangeTile({
    super.key,
    required this.change,
    required this.formatTime,
    required this.sourceType,
    required this.isLatest,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The rail: dot for this change, line continuing to the next.
          SizedBox(
            width: 16,
            child: Column(
              children: [
                const SizedBox(height: 9),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    // The newest change is filled; older ones are hollow. The
                    // timeline then reads newest-first at a glance.
                    color: isLatest ? t.accent : t.background,
                    border: Border.all(color: isLatest ? t.accent : t.border, width: 1.5),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast) Expanded(child: Container(width: 1, color: t.border)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.border.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        formatTime(change.time),
                        style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 10),
                      ),
                      // Only some sources carry an event — a bloc's transition
                      // does, a plain cubit emit or a ValueNotifier set does not.
                      if (change.event != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: t.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              change.event.toString(),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: DebugTextStyles.debugMono(
                                color: t.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  _StateLine(label: '−', value: change.from, isRemoval: true, sourceType: sourceType),
                  const SizedBox(height: 2),
                  _StateLine(label: '+', value: change.to, isRemoval: false, sourceType: sourceType),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One side of a change — the before (`−`) or the after (`+`).
///
/// Tinted like a diff: the outgoing value recedes, the incoming one is the
/// result you're looking for. The `−`/`+` gutter carries the same meaning
/// without colour.
class _StateLine extends StatelessWidget {
  final String label;
  final Object? value;
  final bool isRemoval;
  final String sourceType;

  const _StateLine({
    required this.label,
    required this.value,
    required this.isRemoval,
    required this.sourceType,
  });

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final color = isRemoval ? t.textMuted : t.text;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isRemoval ? t.error.withValues(alpha: 0.05) : t.success.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 12,
            child: Text(
              label,
              style: DebugTextStyles.debugMono(
                color: isRemoval ? t.error.withValues(alpha: 0.7) : t.success,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              // Same formatting as the current-state line, so from/to read
              // consistently — a source-scoped/state-type formatter or the
              // pretty List/Map dump.
              DevtrayState.instance.display(value, sourceType: sourceType),
              style: DebugTextStyles.debugMono(color: color, fontSize: 11, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
