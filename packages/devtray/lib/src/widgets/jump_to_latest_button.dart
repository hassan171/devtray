import 'package:flutter/material.dart';

import '../core/devtray_theme.dart';

/// Returns a live list to its newest entry, and says how much arrived while you
/// were reading something else.
///
/// Shared by the Logs and Network pages, which have the same problem: both are
/// fed by a ring buffer that keeps filling while you scroll back through it.
/// Once a list holds your position instead of dragging you along, it needs to
/// tell you what you're missing and offer a way back — otherwise "held in place"
/// is indistinguishable from "stopped working".
///
/// Float it over the list rather than putting it in the toolbar. It only exists
/// while you're scrolled away, and a control that appears and disappears in the
/// header would shift the list under you — the exact problem the surrounding
/// feature is about.
///
/// ```dart
/// Positioned(
///   left: 0,
///   right: 0,
///   bottom: 8,
///   child: Center(child: JumpToLatestButton(missed: 12, onTap: _jumpToLatest)),
/// )
/// ```
class JumpToLatestButton extends StatelessWidget {
  /// How many entries arrived since the reader scrolled away. Zero falls back
  /// to a plain label — the button still works, it just has no count to report.
  final int missed;

  final VoidCallback onTap;

  const JumpToLatestButton({super.key, required this.missed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: t.accent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_downward, size: 12, color: t.background),
              const SizedBox(width: 5),
              Text(
                // The count matters: "47 new" and "1 new" are different
                // decisions about whether to look now.
                missed > 0 ? '$missed new' : 'Jump to latest',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.background),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
