import 'package:flutter/material.dart';

import '../errors/error_store.dart';
import 'debug_overlay_theme.dart';

/// The draggable floating bug button. Positioned by the parent overlay; this
/// widget only draws it.
///
/// When errors have been captured since the Errors page was last opened, a
/// count badge appears — that's the whole point of capturing them, since
/// nobody is watching the console on a device.
class DebugLauncherButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final DebugOverlayTheme theme;

  /// Set false to suppress the unseen-error badge.
  final bool showErrorBadge;

  const DebugLauncherButton({
    super.key,
    required this.theme,
    this.size = 48,
    this.icon = Icons.bug_report,
    this.showErrorBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.launcherBackground,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Icon(icon, color: theme.launcherIcon, size: size * 0.5),
    );

    return Material(
      color: Colors.transparent,
      child: showErrorBadge
          ? ValueListenableBuilder<int>(
              valueListenable: ErrorStore.instance.unseenCount,
              builder: (context, count, child) => Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topLeft,
                children: [
                  child!,
                  if (count > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: _Badge(count: count, color: theme.error),
                    ),
                ],
              ),
              child: button,
            )
          : button,
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  final Color color;

  const _Badge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        // Stadium, not a circle — "99+" would distort a circle.
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, height: 1),
      ),
    );
  }
}
