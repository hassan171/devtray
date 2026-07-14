import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import 'components/network_detail_pane.dart';
import 'components/network_log_row.dart';
import 'components/network_search_bar.dart';
import 'mocking/mocks_debug_page.dart';
import 'network_log_store.dart';

/// The built-in network inspector page. Reads from [NetworkLogStore], which is
/// fed by [DebugDioInterceptor], [DebugHttpClient], or your own adapter.
///
/// Narrow layouts (below [wideBreakpoint]) show the list OR the detail; wide
/// layouts show them side by side.
class NetworkDebugPage extends DebugPage {
  /// Width at or above which the list and detail are shown side by side.
  final double wideBreakpoint;

  /// Whether this page offers the mocking affordances — the "Mock this request"
  /// button and the interception warning banner.
  ///
  /// Leave it on only if you also register a [MocksDebugPage]: without one,
  /// "Mock this request" would create a rule the user has no way to see, edit or
  /// delete. Set it to false to drop mocking from the UI entirely.
  ///
  /// This is UI only. Rules added from code still apply — see
  /// [MockStore.disable] to turn interception off for real.
  final bool enableMocking;

  const NetworkDebugPage({this.wideBreakpoint = 700, this.enableMocking = true});

  @override
  String get title => 'Network';

  @override
  IconData? get icon => Icons.swap_vert;

  @override
  Widget build(BuildContext context) => _NetworkDebugView(
        wideBreakpoint: wideBreakpoint,
        enableMocking: enableMocking,
      );
}

class _NetworkDebugView extends StatefulWidget {
  final double wideBreakpoint;
  final bool enableMocking;

  const _NetworkDebugView({required this.wideBreakpoint, required this.enableMocking});

  @override
  State<_NetworkDebugView> createState() => _NetworkDebugViewState();
}

class _NetworkDebugViewState extends State<_NetworkDebugView> {
  String _search = '';
  int? _selectedId;

  List<NetworkLogEntry> _filtered(List<NetworkLogEntry> entries) {
    if (_search.isEmpty) return entries;
    final q = _search.toLowerCase();
    return entries.where((e) {
      return e.method.toLowerCase().contains(q) || e.uri.toString().toLowerCase().contains(q) || (e.statusCode?.toString().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final store = NetworkLogStore.instance;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= widget.wideBreakpoint;

        return ValueListenableBuilder<int>(
          valueListenable: store.tick,
          builder: (context, _, _) {
            final entries = store.entries;
            final filtered = _filtered(entries);
            NetworkLogEntry? selected;
            for (final e in entries) {
              if (e.id == _selectedId) selected = e;
            }

            // Narrow: detail replaces the list entirely.
            if (!isWide && selected != null) {
              return NetworkDetailPane(entry: selected, enableMocking: widget.enableMocking, onBack: () => setState(() => _selectedId = null));
            }

            final list = Column(
              children: [
                // Warns when mocks are intercepting, so a faked response can't
                // be mistaken for real server behaviour.
                if (widget.enableMocking) ...[
                  const MockInterceptionBanner(),
                  const SizedBox(height: 8),
                ],
                NetworkSearchBar(
                  total: filtered.length,
                  onChanged: (v) => setState(() => _search = v),
                  onClear: () {
                    store.clear();
                    setState(() => _selectedId = null);
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(entries.isEmpty ? 'No requests yet' : 'No matches', style: TextStyle(color: t.textMuted)),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, i) => NetworkLogRow(
                            entry: filtered[i],
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
                      ? Center(
                          child: Text('Select a request to see details', style: TextStyle(color: t.textMuted)),
                        )
                      : NetworkDetailPane(entry: selected, enableMocking: widget.enableMocking, onBack: () => setState(() => _selectedId = null)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
