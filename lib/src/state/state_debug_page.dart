import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import '../widgets/debug_search_bar.dart';
import 'components/state_detail_pane.dart';
import 'components/state_row.dart';
import 'state_inspector.dart';

/// Every state source the app has created, its **live state**, and its change
/// history — cubits, blocs, or anything else pushed into [StateInspector].
///
/// For bloc, install the adapter:
///
/// ```dart
/// Bloc.observer = DebugBlocObserver();
/// ```
///
/// For other libraries, feed [StateInspector] directly (see `state_bridge.dart`).
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
    final t = DebugOverlayTheme.of(context);
    final store = StateInspector.instance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= widget.wideBreakpoint;

        return ValueListenableBuilder<int>(
          valueListenable: store.tick,
          builder: (context, _, _) {
            final all = store.sources;
            final q = _search.toLowerCase();
            final filtered = q.isEmpty ? all : all.where((b) => b.type.toLowerCase().contains(q)).toList();

            TrackedSource? selected;
            for (final b in all) {
              if (b.id == _selectedId) selected = b;
            }

            // Narrow: the detail replaces the list.
            if (!isWide && selected != null) {
              return StateDetailPane(source: selected, onBack: () => setState(() => _selectedId = null), onRefresh: () => setState(() {}));
            }

            final list = Column(
              children: [
                DebugSearchBar(
                  hintText: 'Search sources',
                  total: filtered.length,
                  onChanged: (v) => setState(() => _search = v),
                  actions: [
                    IconButton(
                      tooltip: 'Clear closed',
                      icon: Icon(Icons.delete_sweep_outlined, size: 18, color: t.textMuted),
                      onPressed: () {
                        store.clearClosed();
                        setState(() => _selectedId = null);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            all.isEmpty
                                ? 'No state sources seen yet.\nDid you install an observer '
                                    '(e.g. Bloc.observer = DebugBlocObserver()),\nor push into StateInspector?'
                                : 'No matches',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: t.textMuted),
                          ),
                        )
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
                      ? Center(child: Text('Select a source to see its state', style: TextStyle(color: t.textMuted)))
                      : StateDetailPane(source: selected, onBack: () => setState(() => _selectedId = null), onRefresh: () => setState(() {})),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
