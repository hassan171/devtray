import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';

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

  const VisualDebugFlag({required this.label, required this.description, required this.get, required this.set});
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
    get: () => debugPaintSizeEnabled,
    set: (v) => debugPaintSizeEnabled = v,
  ),
  VisualDebugFlag(
    label: 'Repaint rainbow',
    description:
        'Recolour a layer each time it repaints. A patch that keeps flashing is repainting every frame — usually a missing const or a RepaintBoundary.',
    get: () => debugRepaintRainbowEnabled,
    set: (v) => debugRepaintRainbowEnabled = v,
  ),
  VisualDebugFlag(
    label: 'Paint baselines',
    description: 'Show text baselines. Use when text sits a pixel or two off from what it should line up with.',
    get: () => debugPaintBaselinesEnabled,
    set: (v) => debugPaintBaselinesEnabled = v,
  ),
  VisualDebugFlag(
    label: 'Highlight taps',
    description: 'Flash the area that received a pointer event. Shows you what actually got the tap when the wrong thing responds — or nothing does.',
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

  bool get _anyOn => widget.flags.any((f) => f.get());

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_anyOn) _ActiveBanner(theme: t, onReset: () => _apply(_resetAll)),
        Expanded(
          child: ListView(
            children: [
              for (final flag in widget.flags)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: flag.get(),
                  onChanged: (v) => _apply(() => flag.set(v)),
                  activeThumbColor: t.accent,
                  title: Text(flag.label, style: TextStyle(fontSize: 13, color: t.text)),
                  subtitle: Text(flag.description, style: TextStyle(fontSize: 11, color: t.textMuted)),
                ),
              const SizedBox(height: 8),
            ],
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

/// These flags are process-wide and survive closing the overlay — a rainbow
/// left on looks like a rendering bug. Make it obvious, and one tap to undo.
class _ActiveBanner extends StatelessWidget {
  final DebugOverlayTheme theme;
  final VoidCallback onReset;

  const _ActiveBanner({required this.theme, required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.warning.withValues(alpha: 0.15),
        border: Border.all(color: theme.warning),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 16, color: theme.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Debug painting is on — what you see is not how the app really looks.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.text),
            ),
          ),
          TextButton(
            onPressed: onReset,
            child: Text('Reset all', style: TextStyle(fontSize: 11, color: theme.warning)),
          ),
        ],
      ),
    );
  }
}
