import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';
import '../../widgets/copyable_section.dart';
import '../state_inspector.dart';

/// One source in full: its live state, any error, and every change it has
/// made — newest first.
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
  /// The change history can be long and is the noisiest part of the pane —
  /// collapsed by default so the state + fields are what you see first.
  bool _changesExpanded = false;

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final source = widget.source;

    // Read on every build, so the values are live rather than a snapshot from
    // whenever the source last emitted.
    final fields = StateInspector.instance.liveFieldsOf(source);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.text),
              ),
            ),
            if (source.isClosed)
              Text('closed', style: TextStyle(fontSize: 10, color: t.textMuted)),
          ],
        ),
        Divider(color: t.border),
        Expanded(
          child: ListView(
            children: [
              CopyableSection(title: 'Current state', body: StateInspector.instance.display(source.state, sourceType: source.type)),

              // Fields the source holds OUTSIDE its state — a sync queue, a
              // lookup map, a retry counter. Read live from the instance on every
              // rebuild, so they're current. See StateInspector.inspect.
              if (fields.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Fields',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.text),
                    ),
                    const SizedBox(width: 4),
                    // These change WITHOUT an emit — a queue gets pushed, a
                    // counter ticks — and the page only rebuilds on emits. So
                    // there has to be a way to re-read them.
                    IconButton(
                      tooltip: 'Re-read fields',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      icon: Icon(Icons.refresh, size: 14, color: t.textMuted),
                      onPressed: widget.onRefresh,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(6)),
                  child: Column(
                    children: [
                      for (final e in fields.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 110,
                                child: Text(e.key, style: TextStyle(fontSize: 11, color: t.textMuted)),
                              ),
                              Expanded(
                                child: SelectableText(
                                  e.value?.toString() ?? 'null',
                                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: t.text),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              if (source.error != null)
                CopyableSection(
                  title: 'Error',
                  titleColor: t.error,
                  body: '${source.error}\n\n${source.stackTrace ?? ''}',
                ),

              const SizedBox(height: 12),
              // Collapsible — the history is the longest, noisiest part of the
              // pane, so it's closed by default and the state/fields lead.
              // GestureDetector, not InkWell — no ripple, and no splash
              // animation for pumpAndSettle to hang on in tests.
              GestureDetector(
                onTap: () => setState(() => _changesExpanded = !_changesExpanded),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(_changesExpanded ? Icons.expand_more : Icons.chevron_right, size: 18, color: t.textMuted),
                      const SizedBox(width: 2),
                      Text(
                        'Changes',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.text),
                      ),
                      const SizedBox(width: 8),
                      Text('${source.changes.length}', style: TextStyle(fontSize: 11, color: t.textMuted)),
                    ],
                  ),
                ),
              ),

              if (_changesExpanded) ...[
                const SizedBox(height: 4),
                if (source.changes.isEmpty)
                  Text(
                    'No changes yet — this source is still on its initial state.',
                    style: TextStyle(fontSize: 11, color: t.textMuted),
                  )
                else
                  for (final change in source.changes) _ChangeTile(change: change, theme: t, formatTime: _formatTime, sourceType: source.type),
              ],

              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChangeTile extends StatelessWidget {
  final StateChangeEntry change;
  final DebugOverlayTheme theme;
  final String Function(DateTime) formatTime;
  final String sourceType;

  const _ChangeTile({required this.change, required this.theme, required this.formatTime, required this.sourceType});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                formatTime(change.time),
                style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: theme.textMuted),
              ),
              // Only some sources carry an event — a bloc's transition does, a
              // plain cubit emit or a ValueNotifier set does not.
              if (change.event != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    change.event.toString(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.accent),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          _StateLine(label: '−', value: change.from, color: theme.textMuted, theme: theme, sourceType: sourceType),
          _StateLine(label: '+', value: change.to, color: theme.text, theme: theme, sourceType: sourceType),
        ],
      ),
    );
  }
}

class _StateLine extends StatelessWidget {
  final String label;
  final Object? value;
  final Color color;
  final DebugOverlayTheme theme;
  final String sourceType;

  const _StateLine({required this.label, required this.value, required this.color, required this.theme, required this.sourceType});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 14,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: theme.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            // Same formatting as the current-state line, so from/to read
            // consistently — a source-scoped/state-type formatter or the pretty
            // List/Map dump.
            StateInspector.instance.display(value, sourceType: sourceType),
            style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: color),
          ),
        ),
      ],
    );
  }
}
