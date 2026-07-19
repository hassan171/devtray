import 'package:flutter/material.dart';

import '../core/devtray_theme.dart';
import '../core/debug_page.dart';
import '../core/debug_text_styles.dart';
import '../widgets/debug_search_bar.dart';
import 'components/state_detail_pane.dart';
import 'components/state_row.dart';
import 'devtray_state.dart';

/// Every state source the app has created, its **live state**, and its change
/// history — cubits, blocs, or anything else pushed into [DevtrayState].
///
/// For bloc, install the adapter:
///
/// ```dart
/// Bloc.observer = DebugBlocObserver();
/// ```
///
/// For other libraries, feed [DevtrayState] directly (see `state_bridge.dart`).
///
/// Narrow layouts show the list OR the detail; wide layouts show both.
class StateDebugPage extends DebugPage {
  /// Width at or above which the list and detail sit side by side.
  final double wideBreakpoint;

  const StateDebugPage({this.wideBreakpoint = 700});

  @override
  String get title => 'State';

  @override
  IconData? get icon => Icons.account_tree_outlined;

  @override
  Widget build(BuildContext context) => _StateView(wideBreakpoint: wideBreakpoint);
}

class _StateView extends StatefulWidget {
  final double wideBreakpoint;
  const _StateView({required this.wideBreakpoint});

  @override
  State<_StateView> createState() => _StateViewState();
}

class _StateViewState extends State<_StateView> {
  String _search = '';
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final store = DevtrayState.instance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= widget.wideBreakpoint;

        return ValueListenableBuilder<int>(
          valueListenable: store.tick,
          builder: (context, _, _) {
            final all = store.sources;
            final q = _search.toLowerCase();
            // Search the type AND the live state — the state is half of what's
            // on the row, so a query that can't reach it looks broken.
            final filtered = q.isEmpty
                ? all
                : all.where((b) {
                    if (b.type.toLowerCase().contains(q)) return true;
                    return store.display(b.state, sourceType: b.type).toLowerCase().contains(q);
                  }).toList();

            TrackedSource? selected;
            for (final b in all) {
              if (b.id == _selectedId) selected = b;
            }

            // Narrow: the detail replaces the list.
            if (!isWide && selected != null) {
              return StateDetailPane(
                source: selected,
                onBack: () => setState(() => _selectedId = null),
                onRefresh: () => setState(() {}),
              );
            }

            final hasClosed = all.any((b) => b.isClosed);

            final list = Column(
              children: [
                DebugSearchBar(
                  hintText: 'Search sources',
                  total: filtered.length,
                  onChanged: (v) => setState(() => _search = v),
                  actions: [
                    IconButton(
                      tooltip: 'Clear closed',
                      // Disabled rather than hidden when nothing is closed: a
                      // button that vanishes moves the ones beside it.
                      onPressed: hasClosed
                          ? () {
                              store.clearClosed();
                              setState(() => _selectedId = null);
                            }
                          : null,
                      icon: Icon(
                        Icons.delete_sweep_outlined,
                        size: 18,
                        color: t.textMuted.withValues(alpha: hasClosed ? 1 : 0.38),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? _EmptyState(isFiltered: all.isNotEmpty, query: _search)
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, i) => StateRow(
                            source: filtered[i],
                            isSelected: filtered[i].id == _selectedId,
                            onTap: () => setState(() => _selectedId = filtered[i].id),
                          ),
                        ),
                ),
              ],
            );

            if (!isWide) return list;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 40, child: list),
                const SizedBox(width: 12),
                Container(width: 1, color: t.border),
                const SizedBox(width: 12),
                Expanded(
                  flex: 60,
                  child: selected == null
                      ? _NoSelection()
                      : StateDetailPane(
                          source: selected,
                          onBack: () => setState(() => _selectedId = null),
                          onRefresh: () => setState(() {}),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Nothing to show — either the app pushed nothing, or the filter matched
/// nothing. Two different problems, so two different messages.
class _EmptyState extends StatelessWidget {
  final bool isFiltered;
  final String query;

  const _EmptyState({required this.isFiltered, required this.query});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    if (isFiltered) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 28, color: t.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Text('No source matches', style: TextStyle(fontSize: 13, color: t.text)),
            const SizedBox(height: 2),
            Text(
              '"$query"',
              style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    // Nothing has been pushed at all. This is nearly always a setup problem, so
    // the empty state is where the setup is documented — the alternative is the
    // user going to the README to find out why their page is blank.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined, size: 32, color: t.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              'No state sources yet',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text),
            ),
            const SizedBox(height: 4),
            Text(
              'Nothing has been pushed into DevtrayState. Install an observer:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.4),
            ),
            const SizedBox(height: 12),
            _CodeHint(lines: const [
              'Bloc.observer = DebugBlocObserver();',
              'ProviderScope(observers: [DebugRiverpodObserver()])',
            ]),
            const SizedBox(height: 10),
            Text(
              'Or push into DevtrayState.instance directly.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// The setup snippets, rendered as code because that's what they are.
class _CodeHint extends StatelessWidget {
  final List<String> lines;
  const _CodeHint({required this.lines});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelectableText(
                line,
                style: DebugTextStyles.debugMono(color: t.text, fontSize: 10, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wide layout, nothing picked yet.
class _NoSelection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back_rounded, size: 20, color: t.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            'Select a source to see its state',
            style: TextStyle(fontSize: 12, color: t.textMuted),
          ),
        ],
      ),
    );
  }
}
