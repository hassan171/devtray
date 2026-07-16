import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import '../core/debug_text_styles.dart';
import 'components/network_detail_pane.dart';
import 'html_previewer.dart';
import 'components/network_log_row.dart';
import 'components/network_search_bar.dart';
import 'mocking/mock_store.dart';
import 'mocking/mocks_view.dart';
import 'network_log_store.dart';

/// The built-in network inspector page. Reads from [NetworkLogStore], which is
/// fed by `DebugDioInterceptor`, `DebugHttpClient`, or your own adapter.
///
/// Narrow layouts (below [wideBreakpoint]) show the list OR the detail; wide
/// layouts show them side by side.
///
/// ## Turning mocking off
///
/// One switch, and it isn't here:
///
/// ```dart
/// MockStore.instance.disable();
/// ```
///
/// The page reads [MockStore.isDisabled] and drops the Mocks button, the "Mock
/// this request" action and the interception warning along with it. There used
/// to be a separate `enableMocking` flag for the UI, which meant the two could
/// disagree — hiding the UI while rules added from code went on faking traffic
/// with nothing on screen to reveal it. That state is now unrepresentable.
class NetworkDebugPage extends DebugPage {
  /// Width at or above which the list and detail are shown side by side.
  final double wideBreakpoint;

  /// Which failed requests are forwarded to the Logs page (and badge the
  /// launcher). Defaults to [NetworkErrorReporting.all] — every failure. Pass a
  /// narrower mode to cut routine 4xx noise. Applied to
  /// [NetworkLogStore.errorReporting] when the page builds; code can still
  /// override it at any time.
  final NetworkErrorReporting errorReporting;

  /// Renders an HTML response body when the preview button is tapped.
  ///
  /// Null — the default — hides the button entirely. The core has no HTML
  /// renderer (see [DebugHtmlPreviewer]); install `debug_overlay_html` and pass
  /// its dialog to get one:
  ///
  /// ```dart
  /// NetworkDebugPage(onPreviewHtml: HtmlPreviewDialog.show)
  /// ```
  final DebugHtmlPreviewer? onPreviewHtml;

  const NetworkDebugPage({
    this.wideBreakpoint = 700,
    this.errorReporting = NetworkErrorReporting.all,
    this.onPreviewHtml,
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
    return _NetworkDebugView(wideBreakpoint: wideBreakpoint, onPreviewHtml: onPreviewHtml);
  }
}

class _NetworkDebugView extends StatefulWidget {
  final double wideBreakpoint;
  final DebugHtmlPreviewer? onPreviewHtml;

  const _NetworkDebugView({required this.wideBreakpoint, required this.onPreviewHtml});

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
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(Icons.arrow_back, size: 16, color: t.textMuted),
                onPressed: () => setState(() => _showMocks = false),
              ),
              const SizedBox(width: 6),
              Text('Mocks', style: DebugTextStyles.label(color: t.text, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Divider(color: t.border, height: 1),
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
            // The store is the single switch: disabling it drops the whole
            // mocking UI, so there's no way to hide the UI while rules keep
            // faking traffic. Read per build — `disable()` can be called at any
            // time, including from a test.
            final mockingEnabled = !MockStore.instance.isDisabled;
            final entries = store.entries;
            final filtered = _filtered(entries);
            NetworkLogEntry? selected;
            for (final e in entries) {
              if (e.id == _selectedId) selected = e;
            }

            // Narrow: detail replaces the list entirely.
            if (!isWide && selected != null) {
              return NetworkDetailPane(
                entry: selected,
                enableMocking: mockingEnabled,
                onPreviewHtml: widget.onPreviewHtml,
                onBack: () => setState(() => _selectedId = null),
              );
            }

            final list = Column(
              children: [
                // The interception warning lives *inside* the toolbar rather
                // than in a banner above it. A banner is a sibling in this
                // Column, so showing it shoved every row down the moment you
                // toggled a mock. The toolbar is always laid out, so folding the
                // warning into it costs no space and moves nothing — see
                // [NetworkSearchBar].
                NetworkSearchBar(
                  total: filtered.length,
                  onChanged: (v) => setState(() => _search = v),
                  onClear: () {
                    store.clear();
                    setState(() => _selectedId = null);
                  },
                  onMocks: mockingEnabled ? () => setState(() => _showMocks = true) : null,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? _NetworkEmptyState(searching: entries.isNotEmpty)
                      : ListView.builder(
                          // The list is the hot path — a chatty app fills it fast,
                          // and builder + itemExtent keeps scrolling flat.
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
                      ? _DetailPlaceholder()
                      : NetworkDetailPane(
                entry: selected,
                enableMocking: mockingEnabled,
                onPreviewHtml: widget.onPreviewHtml,
                onBack: () => setState(() => _selectedId = null),
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

/// Shown when the list has nothing to show.
///
/// An empty tool is the first thing a new user sees, and "No requests yet"
/// centred in a void doesn't say whether the tool is working, broken, or
/// waiting. So it names the state and — when nothing has been captured at all —
/// says what has to happen next, since the usual cause is an adapter that was
/// never installed.
class _NetworkEmptyState extends StatelessWidget {
  /// True when entries exist but the filter excluded them all — a very
  /// different situation from having captured nothing.
  final bool searching;

  const _NetworkEmptyState({required this.searching});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.swap_vert,
              size: 28,
              color: t.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              searching ? 'No matching requests' : 'No requests captured',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text),
            ),
            const SizedBox(height: 4),
            Text(
              searching
                  ? 'Nothing matches this filter.'
                  : 'Traffic shows up here once an adapter is installed —\n'
                      'add DebugDioInterceptor() or wrap your client\n'
                      'in DebugHttpClient().',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// The right-hand pane before a request is picked. Only ever seen on wide
/// layouts, where the list alone would leave half the screen blank.
class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder();

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.multiple_stop, size: 24, color: t.textMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(
            'Select a request',
            style: TextStyle(fontSize: 12, color: t.textMuted),
          ),
        ],
      ),
    );
  }
}
