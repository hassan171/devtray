import 'package:flutter/material.dart';

import '../../core/devtray_theme.dart';
import '../../core/debug_text_styles.dart';
import '../../widgets/copyable_section.dart';
import '../../widgets/debug_tab_bar.dart';
import '../curl_builder.dart';
import '../html_previewer.dart';
import '../mocking/components/mock_rule_editor.dart';
import '../devtray_net.dart';
import 'network_badges.dart';
import 'network_formatters.dart';

/// One detail tab: a label and the sections shown inside it.
class _DetailTab {
  final String name;
  final List<Widget> sections;
  const _DetailTab(this.name, this.sections);
}

/// Right-hand (or full-screen, on phones) pane showing one request in full:
/// headers, bodies, timing, plus copy-as-cURL and HTML preview actions.
class NetworkDetailPane extends StatefulWidget {
  final NetworkLogEntry entry;
  final VoidCallback onBack;

  /// Shows the "Mock this request" action.
  ///
  /// The page passes `!DevtrayMocks.isDisabled` — with the store off, this would
  /// create a rule that can't intercept and that no UI can reach.
  final bool enableMocking;

  /// Renders an HTML response body. Null hides the preview button — the core has
  /// no HTML renderer of its own, so there'd be nothing behind it.
  final DebugHtmlPreviewer? onPreviewHtml;

  const NetworkDetailPane({
    super.key,
    required this.entry,
    required this.onBack,
    this.enableMocking = true,
    this.onPreviewHtml,
  });

  @override
  State<NetworkDetailPane> createState() => _NetworkDetailPaneState();
}

class _NetworkDetailPaneState extends State<NetworkDetailPane> with TickerProviderStateMixin {
  TabController? _tabController;
  int _tabCount = 0;

  // Tabs are dynamic (Error and any extras are conditional), so the controller
  // is rebuilt whenever the visible tab count changes — including when a
  // different request is selected.
  TabController _controllerFor(int length) {
    if (_tabController == null || _tabCount != length) {
      _tabController?.dispose();
      _tabController = TabController(length: length, vsync: this);
      _tabCount = length;
    }
    return _tabController!;
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  List<_DetailTab> _buildTabs(NetworkLogEntry e, DevtrayTheme t) {
    return [
      if (e.errorMessage != null) _DetailTab('Error', [CopyableSection(title: 'Error', body: e.errorMessage!, titleColor: t.error)]),
      _DetailTab('Request', [
        CopyableSection(title: 'Request Headers', body: prettyMap(e.requestHeaders)),
        if (e.queryParameters.isNotEmpty) CopyableSection(title: 'Query Parameters', body: prettyMap(e.queryParameters)),
        CopyableSection(title: 'Request Body', body: prettyJson(e.requestBody)),
      ]),
      _DetailTab('Response', [
        CopyableSection(title: 'Response Headers', body: prettyHeaders(e.responseHeaders)),
        CopyableSection(title: 'Response Body', body: prettyJson(e.responseBody)),
      ]),
      for (final extra in e.extras.entries) _DetailTab(extra.key, [CopyableSection(title: extra.key, body: extra.value)]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final e = widget.entry;
    final tabs = _buildTabs(e, t);
    final controller = _controllerFor(tabs.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: MethodBadge(method: e.method),
            ),
            const SizedBox(width: 8),
            Expanded(
              // The URL is the request's identity and the thing you copy out of
              // here — mono, and selectable so a path can be lifted verbatim.
              child: SelectableText(
                e.uri.toString(),
                style: DebugTextStyles.debugMono(color: t.text, fontSize: 13, fontWeight: FontWeight.w500, height: 1.35),
                maxLines: 2,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Close',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.close, size: 18, color: t.textMuted),
              onPressed: widget.onBack,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 14,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // The outcome is why you opened this pane — give it the badge
                  // treatment (colour + glyph) instead of hiding the code in a
                  // row of neutral label:value pairs.
                  if (e.status == NetworkLogStatus.pending)
                    InfoChip(label: 'Status', value: 'pending')
                  else
                    StatusBadge(code: e.statusCode, failed: e.status == NetworkLogStatus.failed),
                  InfoChip(label: 'Duration', value: formatDuration(e.duration)),
                  InfoChip(label: 'Started', value: formatTime(e.startedAt)),
                ],
              ),
            ),
            // Two conditions, not one: the body has to *be* HTML, and something
            // has to be able to render it. Without a previewer the core has no
            // HTML renderer at all, so the button would open nothing —
            // isHtmlResponse sniffs the body, so it can only be true when there
            // is one, and no empty-body case needs guarding here.
            if (e.isHtmlResponse && widget.onPreviewHtml != null)
              IconButton(
                tooltip: 'Preview HTML',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(Icons.preview, size: 16, color: t.textMuted),
                onPressed: () => widget.onPreviewHtml!(context, e.responseBodyString!),
              ),
            if (widget.enableMocking)
              IconButton(
                tooltip: 'Mock this request',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                // The one action that changes behaviour rather than just reading
                // — accent-coloured so it isn't mistaken for another copy button.
                icon: Icon(Icons.alt_route, size: 16, color: t.accent),
                // Seeds the rule from this request's real response, so you edit
                // rather than author JSON from scratch.
                onPressed: () => MockRuleEditor.showForEntry(context, e),
              ),
            CopyButton(
              tooltip: 'Copy as cURL',
              icon: Icons.code,
              size: 16,
              // Built on press: this JSON-encodes the whole request body, and
              // the pane rebuilds whenever any *other* request completes.
              text: () => buildCurl(method: e.method, uri: e.uri, headers: e.requestHeaders, data: e.requestBody),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Divider(color: t.border, height: 1),
        DebugTabBar(controller: controller, padding: EdgeInsets.zero, tabs: [for (final tab in tabs) DebugTab(tab.name)]),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: [
              for (final tab in tabs)
                SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...tab.sections, const SizedBox(height: 8)]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
