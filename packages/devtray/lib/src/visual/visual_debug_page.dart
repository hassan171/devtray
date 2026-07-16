import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../core/devtray_theme.dart';
import '../core/debug_page.dart';
import '../core/debug_text_styles.dart';

/// One of Flutter's global rendering debug flags.
///
/// These are plain globals in `package:flutter/rendering.dart`. Flipping one
/// only takes effect on the next paint, so [VisualDebugPage] forces a repaint
/// after every change.
class VisualDebugFlag {
  final String label;
  final String description;
  final bool Function() get;
  final void Function(bool) set;

  /// Shown on the flag's tile. Purely a scanning aid — the label is what the
  /// flag *is*, the icon is how you find it again without reading.
  final IconData icon;

  const VisualDebugFlag({
    required this.label,
    required this.description,
    required this.get,
    required this.set,
    this.icon = Icons.tune_rounded,
  });
}

/// The flags shown by default.
///
/// Deliberately not every debug flag Flutter exposes — most are noise. These are
/// the ones you'd actually reach for, and they're the reason you'd otherwise
/// tether the device to a desktop DevTools session.
final List<VisualDebugFlag> kDefaultVisualDebugFlags = [
  VisualDebugFlag(
    label: 'Paint layout bounds',
    description: 'Outline every box, padding and alignment. The fastest way to see why something is the wrong size.',
    icon: Icons.crop_free_rounded,
    get: () => debugPaintSizeEnabled,
    set: (v) => debugPaintSizeEnabled = v,
  ),
  VisualDebugFlag(
    label: 'Repaint rainbow',
    description:
        'Recolour a layer each time it repaints. A patch that keeps flashing is repainting every frame — usually a missing const or a RepaintBoundary.',
    icon: Icons.gradient_rounded,
    get: () => debugRepaintRainbowEnabled,
    set: (v) => debugRepaintRainbowEnabled = v,
  ),
  VisualDebugFlag(
    label: 'Paint baselines',
    description: 'Show text baselines. Use when text sits a pixel or two off from what it should line up with.',
    icon: Icons.text_fields_rounded,
    get: () => debugPaintBaselinesEnabled,
    set: (v) => debugPaintBaselinesEnabled = v,
  ),
  VisualDebugFlag(
    label: 'Highlight taps',
    description: 'Flash the area that received a pointer event. Shows you what actually got the tap when the wrong thing responds — or nothing does.',
    icon: Icons.touch_app_rounded,
    get: () => debugPaintPointersEnabled,
    set: (v) => debugPaintPointersEnabled = v,
  ),
  // NOTE: `debugPaintLayerBordersEnabled` is deliberately absent.
  //
  // It's drawn in `PaintingContext.stopRecordingIfNeeded`, i.e. only when a
  // layer records a *new* picture — not on every repaint like the flags above.
  // Layers whose picture is already cached never re-record, so the borders never
  // appear. Neither a full render-tree `markNeedsPaint()` walk nor
  // `reassembleApplication()` reliably forces every layer to re-record from
  // outside the framework; DevTools gets away with it because it drives the
  // engine directly. Rather than ship a switch that silently does nothing, it's
  // left out. Use DevTools for layer borders.
  VisualDebugFlag(
    label: 'Slow animations',
    description: 'Run every animation at 1/5 speed, so you can actually see what a transition does.',
    icon: Icons.slow_motion_video_rounded,
    get: () => timeDilation != 1.0,
    set: (v) => timeDilation = v ? 5.0 : 1.0,
  ),
];

/// Flutter's rendering debug flags, as switches — the on-device substitute for
/// a tethered DevTools session.
///
/// The flags are process-wide globals, so they stay on until you turn them off
/// (or the app restarts). The page offers a "reset all" for exactly that reason:
/// leaving the repaint rainbow on is easy, and confusing.
class VisualDebugPage extends DebugPage {
  /// Override to add your own toggles, or trim the list.
  final List<VisualDebugFlag> flags;

  VisualDebugPage({List<VisualDebugFlag>? flags}) : flags = flags ?? kDefaultVisualDebugFlags;

  @override
  String get title => 'Visual';

  @override
  IconData? get icon => Icons.grid_on;

  @override
  Widget build(BuildContext context) => _VisualDebugView(flags: flags);
}

class _VisualDebugView extends StatefulWidget {
  final List<VisualDebugFlag> flags;
  const _VisualDebugView({required this.flags});

  @override
  State<_VisualDebugView> createState() => _VisualDebugViewState();
}

class _VisualDebugViewState extends State<_VisualDebugView> {
  /// The flags only take effect on the next paint, and nothing marks anything
  /// dirty when a plain global changes — so force a repaint.
  ///
  /// This mirrors `RendererBinding._forceRepaint`, which is what Flutter's own
  /// `ext.flutter.debugPaint` service extension (i.e. the DevTools toggle) calls.
  /// It walks the **render** tree from every [RenderView]. Walking the *element*
  /// tree instead misses render objects, and the flags then only appear to work
  /// on parts of the app — which is exactly what happens if you get this wrong.
  ///
  /// Deliberately not `reassembleApplication()`: that rebuilds the whole widget
  /// tree (it's the hot-reload path) and re-enters `runApp`, which trips a
  /// scheduler assertion under `flutter_test`.
  void _apply(VoidCallback change) {
    setState(change);
    _forceRepaint();
  }

  void _forceRepaint() {
    late RenderObjectVisitor visitor;
    visitor = (RenderObject child) {
      child.markNeedsPaint();
      child.visitChildren(visitor);
    };
    for (final renderView in RendererBinding.instance.renderViews) {
      renderView.visitChildren(visitor);
    }
  }

  int get _onCount => widget.flags.where((f) => f.get()).length;

  @override
  Widget build(BuildContext context) {
    final onCount = _onCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reserved space, not a conditional child: a banner that appears on the
        // first toggle would shove the whole list down under the finger that
        // just tapped, and the switch you aimed at moves out from under you.
        // Same reason the Network page's mock badge sits in a fixed slot.
        _ActiveBanner(onCount: onCount, onReset: () => _apply(_resetAll)),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: widget.flags.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, i) => _FlagTile(
              flag: widget.flags[i],
              onChanged: (v) => _apply(() => widget.flags[i].set(v)),
            ),
          ),
        ),
      ],
    );
  }

  void _resetAll() {
    for (final flag in widget.flags) {
      flag.set(false);
    }
  }
}

/// One flag: a card that is visibly on or off.
///
/// A `SwitchListTile` puts the entire signal in the switch's thumb — a 20px
/// detail at the far edge, on a page whose whole job is "which of these did I
/// leave on?". So the tile itself carries the state: tinted ground, accent
/// border, coloured icon and label.
class _FlagTile extends StatelessWidget {
  final VisualDebugFlag flag;
  final ValueChanged<bool> onChanged;

  const _FlagTile({required this.flag, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final isOn = flag.get();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        // The whole card toggles — a 40px switch is a needlessly small target
        // when the row is right there. The Switch stays as the affordance.
        onTap: () => onChanged(!isOn),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          decoration: BoxDecoration(
            color: isOn ? t.accent.withValues(alpha: 0.08) : t.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isOn ? t.accent.withValues(alpha: 0.6) : t.border.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Icon(flag.icon, size: 18, color: isOn ? t.accent : t.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      flag.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isOn ? FontWeight.w600 : FontWeight.w500,
                        color: isOn ? t.accent : t.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      flag.description,
                      style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Excluded from semantics: the InkWell already exposes the whole
              // card as one toggle, so leaving the Switch focusable would give a
              // screen reader two controls for one flag.
              ExcludeSemantics(
                child: Switch(
                  value: isOn,
                  onChanged: onChanged,
                  activeThumbColor: t.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// These flags are process-wide and survive closing the overlay — a rainbow
/// left on looks like a rendering bug. Make it obvious, and one tap to undo.
///
/// Always occupies its slot; only its contents cross-fade. See the note at the
/// call site — appearing on toggle would move the list under the user's finger.
class _ActiveBanner extends StatelessWidget {
  final int onCount;
  final VoidCallback onReset;

  const _ActiveBanner({required this.onCount, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final isActive = onCount > 0;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: !isActive
          // The resting state still says what the page does, so the slot isn't
          // dead space — and the banner then isn't the only thing here.
          ? Container(
              key: const ValueKey('idle'),
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: t.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Flutter's rendering flags. They stay on until you turn them off.",
                      style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.35),
                    ),
                  ),
                ],
              ),
            )
          : Container(
              key: const ValueKey('active'),
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: t.warning.withValues(alpha: 0.15),
                border: Border.all(color: t.warning),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: t.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Debug painting is on — what you see is not how the app really looks.',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.text),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // The count is the useful part: it tells you there's a second
                  // flag on somewhere below the fold.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: t.warning.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('$onCount', style: DebugTextStyles.label(color: t.warning, fontSize: 10)),
                  ),
                  TextButton(
                    onPressed: onReset,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      'Reset all',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.warning),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
