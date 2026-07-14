import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';
import '../../widgets/copyable_section.dart';
import '../../widgets/debug_tab_bar.dart';
import '../../widgets/html_preview_dialog.dart';
import '../curl_builder.dart';
import '../mocking/components/mock_rule_editor.dart';
import '../network_log_store.dart';
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

  /// Shows the "Mock this request" action. Off when the host app didn't register
  /// a [MocksDebugPage] — otherwise the button would create a rule the user has
  /// no way to see, edit or delete.
  final bool enableMocking;

  const NetworkDetailPane({
    super.key,
    required this.entry,
    required this.onBack,
    this.enableMocking = true,
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

  List<_DetailTab> _buildTabs(NetworkLogEntry e, DebugOverlayTheme t) {
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
    final t = DebugOverlayTheme.of(context);
    final e = widget.entry;
    final tabs = _buildTabs(e, t);
    final controller = _controllerFor(tabs.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            MethodBadge(method: e.method),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                e.uri.toString(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: t.text),
                maxLines: 2,
              ),
            ),
            IconButton(
              tooltip: 'Close',
              icon: Icon(Icons.close, size: 18, color: t.text),
              onPressed: widget.onBack,
            ),
          ],
        ),
        Divider(color: t.border),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  InfoChip(label: 'Status', value: e.statusCode?.toString() ?? (e.status == NetworkLogStatus.pending ? 'pending' : '-')),
                  InfoChip(label: 'Duration', value: formatDuration(e.duration)),
                  InfoChip(label: 'Started', value: formatTime(e.startedAt)),
                ],
              ),
            ),
            // isHtmlResponse sniffs the body, so it can only be true when there
            // is one — no empty-body case to guard against here.
            if (e.isHtmlResponse) ...[
              IconButton(
                tooltip: 'Preview HTML',
                icon: Icon(Icons.preview, size: 16, color: t.text),
                onPressed: () => HtmlPreviewDialog.show(context, e.responseBodyString!),
              ),
              const SizedBox(width: 8),
            ],
            if (widget.enableMocking) ...[
              IconButton(
                tooltip: 'Mock this request',
                icon: Icon(Icons.alt_route, size: 16, color: t.text),
                // Seeds the rule from this request's real response, so you edit
                // rather than author JSON from scratch.
                onPressed: () => MockRuleEditor.showForEntry(context, e),
              ),
              const SizedBox(width: 8),
            ],
            CopyButton(
              tooltip: 'Copy as cURL',
              icon: Icons.code,
              size: 16,
              text: buildCurl(method: e.method, uri: e.uri, headers: e.requestHeaders, data: e.requestBody),
            ),
          ],
        ),
        Divider(color: t.border),
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
