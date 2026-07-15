import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import 'components/network_detail_pane.dart';
import 'components/network_log_row.dart';
import 'components/network_search_bar.dart';
import 'mocking/mocks_view.dart';
import 'network_log_store.dart';

/// The built-in network inspector page. Reads from [NetworkLogStore], which is
/// fed by [DebugDioInterceptor], [DebugHttpClient], or your own adapter.
///
/// Narrow layouts (below [wideBreakpoint]) show the list OR the detail; wide
/// layouts show them side by side.
class NetworkDebugPage extends DebugPage {
  /// Width at or above which the list and detail are shown side by side.
  final double wideBreakpoint;

  /// Whether this tab offers the mocking affordances — the toolbar "Mocks"
  /// button (which opens the [MocksView] in-tab), the "Mock this request" button
  /// on a request's detail, and the interception warning banner.
  ///
  /// On by default. Set it to false to drop mocking from the UI entirely — then
  /// there's no button to reach the rules, so "Mock this request" is hidden too.
  ///
  /// This is UI only. Rules added from code still apply — see
  /// [MockStore.disable] to turn interception off for real.
  final bool enableMocking;

  /// Which failed requests are forwarded to the Errors page (and badge the
  /// launcher). Defaults to [NetworkErrorReporting.all] — every failure. Pass a
  /// narrower mode to cut routine 4xx noise. Applied to
  /// [NetworkLogStore.errorReporting] when the page builds; code can still
  /// override it at any time.
  final NetworkErrorReporting errorReporting;

  const NetworkDebugPage({
    this.wideBreakpoint = 700,
    this.enableMocking = true,
    this.errorReporting = NetworkErrorReporting.all,
  });

  @override
  String get title => 'Network';

  @override
  IconData? get icon => Icons.swap_vert;

  @override
  Widget build(BuildContext context) {
    // The page owns the policy now (no in-app toggle). Set it here so it takes
    // effect as soon as the page is in the tree.
    NetworkLogStore.instance.errorReporting.value = errorReporting;
    return _NetworkDebugView(wideBreakpoint: wideBreakpoint, enableMocking: enableMocking);
  }
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

  /// When true the tab shows the mocking UI (reached via the toolbar button)
  /// instead of the request list. Kept in-tab so mocks don't need their own
  /// registered page.
  bool _showMocks = false;

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

    // The mocking UI lives inside this tab — a back arrow returns to the list.
    if (_showMocks) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to requests',
                icon: Icon(Icons.arrow_back, size: 18, color: t.text),
                onPressed: () => setState(() => _showMocks = false),
              ),
              Text('Mocks', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.text)),
            ],
          ),
          Divider(color: t.border),
          const Expanded(child: MocksView()),
        ],
      );
    }

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
                  onMocks: widget.enableMocking ? () => setState(() => _showMocks = true) : null,
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
