import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import '../widgets/debug_search_bar.dart';
import 'bloc_store.dart';
import 'components/bloc_detail_pane.dart';
import 'components/bloc_row.dart';

/// Every bloc/cubit the app has created, its **live state**, and its transition
/// history.
///
/// Requires the observer:
///
/// ```dart
/// Bloc.observer = DebugBlocObserver();
/// ```
///
/// Narrow layouts show the list OR the detail; wide layouts show both.
class BlocDebugPage extends DebugPage {
  /// Width at or above which the list and detail sit side by side.
  final double wideBreakpoint;

  const BlocDebugPage({this.wideBreakpoint = 700});

  @override
  String get title => 'Blocs';

  @override
  IconData? get icon => Icons.account_tree_outlined;

  @override
  Widget build(BuildContext context) => _BlocView(wideBreakpoint: wideBreakpoint);
}

class _BlocView extends StatefulWidget {
  final double wideBreakpoint;
  const _BlocView({required this.wideBreakpoint});

  @override
  State<_BlocView> createState() => _BlocViewState();
}

class _BlocViewState extends State<_BlocView> {
  String _search = '';
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final store = BlocStore.instance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= widget.wideBreakpoint;

        return ValueListenableBuilder<int>(
          valueListenable: store.tick,
          builder: (context, _, _) {
            final all = store.blocs;
            final q = _search.toLowerCase();
            final filtered = q.isEmpty ? all : all.where((b) => b.type.toLowerCase().contains(q)).toList();

            TrackedBloc? selected;
            for (final b in all) {
              if (b.id == _selectedId) selected = b;
            }

            // Narrow: the detail replaces the list.
            if (!isWide && selected != null) {
              return BlocDetailPane(bloc: selected, onBack: () => setState(() => _selectedId = null), onRefresh: () => setState(() {}));
            }

            final list = Column(
              children: [
                DebugSearchBar(
                  hintText: 'Search cubits',
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
                                ? 'No blocs seen yet.\nDid you set Bloc.observer = DebugBlocObserver()?'
                                : 'No matches',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: t.textMuted),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, i) => BlocRow(
                            bloc: filtered[i],
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
                      ? Center(child: Text('Select a cubit to see its state', style: TextStyle(color: t.textMuted)))
                      : BlocDetailPane(bloc: selected, onBack: () => setState(() => _selectedId = null), onRefresh: () => setState(() {})),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
