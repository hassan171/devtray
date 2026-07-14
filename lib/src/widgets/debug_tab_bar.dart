import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';

/// One entry in a [DebugTabBar].
class DebugTab {
  final String label;
  final IconData? icon;
  const DebugTab(this.label, {this.icon});
}

/// A flat, scrollable underline tab bar — the overlay's only tab style, used
/// both for the top-level pages and for a request's detail tabs.
class DebugTabBar extends StatelessWidget {
  final List<DebugTab> tabs;
  final TabController controller;
  final EdgeInsets padding;

  const DebugTabBar({
    super.key,
    required this.tabs,
    required this.controller,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Padding(
      padding: padding,
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.only(right: 24),
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: t.accent,
        dividerColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelColor: t.accent,
        unselectedLabelColor: t.textMuted,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        tabs: [
          for (final tab in tabs)
            Tab(
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tab.icon != null) ...[Icon(tab.icon, size: 15), const SizedBox(width: 6)],
                  Text(tab.label),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
