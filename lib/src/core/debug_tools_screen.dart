import 'package:flutter/material.dart';

import '../widgets/debug_tab_bar.dart';
import 'debug_overlay_theme.dart';
import 'debug_page.dart';

/// The tabbed debug tools body — one tab per [DebugPage].
///
/// Public so it can be shown however you like: the built-in launcher's dialog,
/// a route you push yourself, a bottom sheet, a side panel. Wrap it in a
/// [DebugOverlayThemeScope] (or pass [theme]) to restyle it.
class DebugToolsScreen extends StatefulWidget {
  final List<DebugPage> pages;
  final DebugOverlayTheme theme;

  /// Shown in the header bar. Omit to hide the close button (e.g. when the
  /// host provides its own chrome).
  final VoidCallback? onClose;

  const DebugToolsScreen({
    super.key,
    required this.pages,
    this.theme = const DebugOverlayTheme(),
    this.onClose,
  });

  @override
  State<DebugToolsScreen> createState() => _DebugToolsScreenState();
}

class _DebugToolsScreenState extends State<DebugToolsScreen> with TickerProviderStateMixin {
  late TabController _controller = TabController(length: widget.pages.length, vsync: this);

  @override
  void didUpdateWidget(DebugToolsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pages can be added/removed at runtime — rebuild the controller so its
    // length never drifts from the tab count.
    if (oldWidget.pages.length != widget.pages.length) {
      _controller.dispose();
      _controller = TabController(length: widget.pages.length, vsync: this);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;

    if (widget.pages.isEmpty) {
      return DebugOverlayThemeScope(
        theme: t,
        child: ColoredBox(
          color: t.background,
          child: Center(child: Text('No debug pages registered', style: TextStyle(color: t.textMuted))),
        ),
      );
    }

    return DebugOverlayThemeScope(
      theme: t,
      child: Material(
        color: t.background,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DebugTabBar(
                      controller: _controller,
                      tabs: [for (final p in widget.pages) DebugTab(p.title, icon: p.icon)],
                    ),
                  ),
                  if (widget.onClose != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.close, color: t.text),
                      onPressed: widget.onClose,
                    ),
                  ],
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _controller,
                  children: [for (final p in widget.pages) Builder(builder: p.build)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
