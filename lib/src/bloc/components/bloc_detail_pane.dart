import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';
import '../../widgets/copyable_section.dart';
import '../bloc_store.dart';

/// One cubit in full: its live state, any error, and every transition it has
/// made — newest first.
class BlocDetailPane extends StatelessWidget {
  final TrackedBloc bloc;
  final VoidCallback onBack;

  /// Re-reads the cubit's non-state fields. They change without an emit, and the
  /// page only rebuilds on emits — so this is the only way to see them update.
  final VoidCallback onRefresh;

  const BlocDetailPane({
    super.key,
    required this.bloc,
    required this.onBack,
    required this.onRefresh,
  });

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    // Read on every build, so the values are live rather than a snapshot from
    // whenever the cubit last emitted.
    final fields = BlocStore.instance.liveFieldsOf(bloc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back, size: 18, color: t.text),
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                bloc.type,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.text),
              ),
            ),
            if (bloc.isClosed)
              Text('closed', style: TextStyle(fontSize: 10, color: t.textMuted)),
          ],
        ),
        Divider(color: t.border),
        Expanded(
          child: ListView(
            children: [
              CopyableSection(title: 'Current state', body: bloc.state?.toString() ?? 'null'),

              // Fields the cubit holds OUTSIDE its state — a sync queue, a lookup
              // map, a retry counter. Read live from the instance on every
              // rebuild, so they're current. See BlocStore.inspect.
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
                      onPressed: onRefresh,
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

              if (bloc.error != null)
                CopyableSection(
                  title: 'Error',
                  titleColor: t.error,
                  body: '${bloc.error}\n\n${bloc.stackTrace ?? ''}',
                ),

              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Transitions',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.text),
                  ),
                  const SizedBox(width: 8),
                  Text('${bloc.changes.length}', style: TextStyle(fontSize: 11, color: t.textMuted)),
                ],
              ),
              const SizedBox(height: 4),

              if (bloc.changes.isEmpty)
                Text(
                  'No transitions yet — this cubit is still on its initial state.',
                  style: TextStyle(fontSize: 11, color: t.textMuted),
                )
              else
                for (final change in bloc.changes) _ChangeTile(change: change, theme: t, formatTime: _formatTime),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChangeTile extends StatelessWidget {
  final BlocChangeEntry change;
  final DebugOverlayTheme theme;
  final String Function(DateTime) formatTime;

  const _ChangeTile({required this.change, required this.theme, required this.formatTime});

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
              // Only a Bloc has events — a plain Cubit's emit has none.
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
          _StateLine(label: '−', value: change.from, color: theme.textMuted, theme: theme),
          _StateLine(label: '+', value: change.to, color: theme.text, theme: theme),
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

  const _StateLine({required this.label, required this.value, required this.color, required this.theme});

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
          child: SelectableText(
            value?.toString() ?? 'null',
            style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: color),
          ),
        ),
      ],
    );
  }
}
