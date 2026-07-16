import 'package:flutter/material.dart';

import '../../core/devtray_theme.dart';
import '../../core/debug_text_styles.dart';
import '../mocking/mock_store.dart';

/// A compact icon action sized for touch.
///
/// The icon is 16px because the toolbar is dense, but the *target* is 36px —
/// a 16px hit area would be a miss-tap generator on a phone. Visual size and
/// touch size are separate concerns.
class _ToolbarAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _ToolbarAction({required this.icon, required this.tooltip, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

/// The Mocks button — and, while anything is intercepting, the interception
/// warning itself.
///
/// This used to be a banner above the toolbar. But a banner is a sibling in the
/// page's Column, so showing it pushed every request row down the moment you
/// toggled a mock, and hid it again on the way back. This button is *always*
/// laid out, so saying it here costs nothing and moves nothing.
///
/// It still has to be impossible to miss — a faked response that looks real
/// costs an afternoon — so while armed it goes solid amber, grows a warning
/// glyph, and states the active rule count.
class _MocksButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _MocksButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final store = MockStore.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([store.offline, store.rulesEnabled, store.rules]),
      builder: (context, _) {
        final intercepting = store.isIntercepting;
        final offline = store.offline.value;
        final active = store.rules.value.where((r) => r.enabled).length;

        // Offline fails *everything*, so a rule count would understate it — the
        // badge says "!" and the tooltip spells it out.
        final label = offline ? '!' : '$active';
        final tooltip = intercepting
            ? (offline
                ? 'Offline mode is ON — every request is being failed. Tap to manage.'
                : '$active mock rule${active == 1 ? '' : 's'} active — some responses are faked. Tap to manage.')
            : 'Mocks';

        return Tooltip(
          message: tooltip,
          child: Semantics(
            button: true,
            label: tooltip,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(6),
              // A fixed box in every state. The label used to sit *beside* the
              // icon, so the button grew when armed and nudged the toolbar —
              // the same layout shift the banner was moved here to avoid, just
              // smaller. The count rides on top of the icon instead, so width
              // can't depend on state (and 'OFFLINE' vs '2' can't either).
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: intercepting ? t.warning.withValues(alpha: 0.18) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          intercepting ? Icons.warning_amber_rounded : Icons.alt_route,
                          size: 16,
                          color: intercepting ? t.warning : t.accent,
                        ),
                        if (intercepting)
                          Positioned(
                            top: -1,
                            right: -3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              constraints: const BoxConstraints(minWidth: 12),
                              height: 12,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: t.warning,
                                borderRadius: BorderRadius.circular(6),
                                // Rings the badge in the bar's own colour so it
                                // reads as separate from the icon underneath.
                                border: Border.all(color: t.surface, width: 1),
                              ),
                              child: Text(
                                label,
                                style: DebugTextStyles.label(
                                  // On the solid warning fill, not on the page.
                                  color: t.background,
                                  fontSize: 8,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Search field + result count + optional Mocks button + clear-all button.
///
/// Presented as one grouped surface rather than a stock `TextField` flanked by
/// loose `IconButton`s: the field, the count and the actions are one toolbar,
/// and drawing them as one object is what separates a tool from a form.
///
/// It doubles as the page's interception warning: while mocks are faking
/// traffic the whole bar goes amber. That's deliberate — the alternative was a
/// banner that shoved the list down every time a mock was toggled.
class NetworkSearchBar extends StatelessWidget {
  final int total;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// Opens the mocking UI inside the Network tab. Null hides the button — used
  /// when mocking is disabled for the page.
  final VoidCallback? onMocks;

  const NetworkSearchBar({super.key, required this.total, required this.onChanged, required this.onClear, this.onMocks});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final store = MockStore.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([store.offline, store.rulesEnabled, store.rules]),
      builder: (context, child) {
        // Only claim to be intercepting when the page actually offers mocking —
        // with the UI disabled there'd be no way to act on the warning.
        final intercepting = onMocks != null && store.isIntercepting;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: intercepting ? t.warning.withValues(alpha: 0.08) : t.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: intercepting ? t.warning.withValues(alpha: 0.7) : t.border.withValues(alpha: 0.8),
              // Same width in both states — a thicker border would resize the
              // box and reintroduce the shift this whole design avoids.
            ),
          ),
          child: child,
        );
      },
      // Built once and reused across interception changes — only the wrapper's
      // colours animate.
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(Icons.search, size: 16, color: t.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              // The query is matched against URLs — mono keeps it honest.
              style: DebugTextStyles.debugMono(color: t.text, fontSize: 13),
              cursorColor: t.accent,
              cursorWidth: 1.5,
              decoration: InputDecoration(
                hintText: 'Filter requests',
                hintStyle: TextStyle(color: t.textMuted, fontSize: 13),
                isDense: true,
                // The container is the frame — the field shouldn't draw a second one.
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: onChanged,
            ),
          ),
          // The count is a live readout of the filter, so it sits with the field
          // rather than floating between the actions.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$total',
              style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          Container(width: 1, height: 20, color: t.border.withValues(alpha: 0.8)),
          if (onMocks != null) _MocksButton(onPressed: onMocks!),
          _ToolbarAction(icon: Icons.delete_outline, tooltip: 'Clear all requests', color: t.error, onPressed: onClear),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}
