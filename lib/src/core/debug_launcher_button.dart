import 'package:flutter/material.dart';

import 'debug_overlay_theme.dart';

/// The draggable floating bug button. Positioned by the parent overlay; this
/// widget only draws it.
class DebugLauncherButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final DebugOverlayTheme theme;

  const DebugLauncherButton({
    super.key,
    required this.theme,
    this.size = 48,
    this.icon = Icons.bug_report,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.launcherBackground,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: const Color(0x4D000000), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(icon, color: theme.launcherIcon, size: size * 0.5),
      ),
    );
  }
}
