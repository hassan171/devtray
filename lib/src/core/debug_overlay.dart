import 'package:flutter/material.dart';
import 'package:hz_toast/hz_toast.dart';

import 'debug_launcher_button.dart';
import 'debug_overlay_controller.dart';
import 'debug_overlay_theme.dart';
import 'debug_page.dart';
import 'debug_tools_screen.dart';

/// How the tools are presented when opened.
///
/// These are drawn as a layer inside the overlay's own Stack, not pushed onto
/// your Navigator — so opening the tools never touches your app's route stack,
/// and back/pop behaviour in your app is unaffected.
enum DebugOverlayPresentation {
  /// A centered panel over a dismissable scrim. Good default on tablet/desktop.
  dialog,

  /// Covers the whole screen.
  fullscreen,

  /// A panel anchored to the bottom, over a dismissable scrim. Good on phones.
  bottomSheet,

  /// Nothing is presented automatically — you render [DebugToolsScreen]
  /// yourself and just use the controller as an on/off signal.
  custom,
}

/// Where the floating launcher button starts.
enum DebugLauncherCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Wrap your app with this to get an in-app debugging overlay.
///
/// Everything about *when* and *how* the tools appear is yours to decide:
///
/// ```dart
/// DebugOverlay(
///   enabled: kDebugMode,                       // when it exists at all
///   showLauncher: true,                        // whether the button is drawn
///   presentation: DebugOverlayPresentation.dialog,
///   controller: myController,                  // open()/close() from anywhere
///   theme: const DebugOverlayTheme.dark(),
///   pages: [
///     const NetworkDebugPage(),
///     DebugPage.builder(title: 'Env', builder: (_) => const MyEnvPage()),
///   ],
///   child: MaterialApp(...),
/// )
/// ```
///
/// With `showLauncher: false` there is no visible affordance at all — call
/// `controller.open()` from your own trigger (shake, 5-tap on the logo, a
/// hidden settings row).
class DebugOverlay extends StatefulWidget {
  /// The app. The overlay is stacked on top of it.
  final Widget child;

  /// The tabs. Order is preserved.
  final List<DebugPage> pages;

  /// Master switch. When false the overlay renders nothing and never captures
  /// gestures — pass `kDebugMode`, an env flag, a remote flag, whatever.
  final bool enabled;

  /// Whether the floating launcher button is drawn. Ignored when a [controller]
  /// is supplied — use `controller.showLauncher` instead, so it can be flipped
  /// at runtime.
  final bool showLauncher;

  /// Supply one to drive the overlay from your own trigger. When omitted, the
  /// overlay creates and owns an internal controller.
  final DebugOverlayController? controller;

  final DebugOverlayPresentation presentation;
  final DebugOverlayTheme theme;

  /// Starting corner of the launcher button. It stays draggable from there.
  final DebugLauncherCorner launcherCorner;
  final EdgeInsets launcherMargin;
  final double launcherSize;
  final IconData launcherIcon;

  /// Show a red count badge on the launcher when errors have been captured but
  /// not yet reviewed. Requires [captureErrors] (or [DebugOverlayCapture]) to
  /// be installed, and is ignored when [launcherBuilder] replaces the button.
  final bool showErrorBadge;

  /// Replaces the default bug button entirely. It's still positioned and
  /// draggable — you only supply the visuals.
  final Widget? launcherBuilder;

  const DebugOverlay({
    super.key,
    required this.child,
    this.pages = const [],
    this.enabled = true,
    this.showLauncher = true,
    this.controller,
    this.presentation = DebugOverlayPresentation.dialog,
    this.theme = const DebugOverlayTheme(),
    this.launcherCorner = DebugLauncherCorner.bottomRight,
    this.launcherMargin = const EdgeInsets.all(16),
    this.launcherSize = 48,
    this.launcherIcon = Icons.bug_report,
    this.showErrorBadge = true,
    this.launcherBuilder,
  });

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  late DebugOverlayController _controller = widget.controller ?? DebugOverlayController(showLauncher: widget.showLauncher);
  bool get _ownsController => widget.controller == null;

  /// Null until first drag — the button then sits wherever it was dropped.
  Offset? _pos;

  @override
  void initState() {
    super.initState();
    _controller.isOpenListenable.addListener(_onOpenChanged);
  }

  @override
  void didUpdateWidget(DebugOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.isOpenListenable.removeListener(_onOpenChanged);
      if (oldWidget.controller == null) oldWidget.controller?.dispose();
      _controller = widget.controller ?? DebugOverlayController(showLauncher: widget.showLauncher);
      _controller.isOpenListenable.addListener(_onOpenChanged);
    }
  }

  @override
  void dispose() {
    _controller.isOpenListenable.removeListener(_onOpenChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onOpenChanged() {
    if (mounted) setState(() {});
  }

  Offset _defaultPos(double maxX, double maxY) {
    final m = widget.launcherMargin;
    return switch (widget.launcherCorner) {
      DebugLauncherCorner.topLeft => Offset(m.left, m.top),
      DebugLauncherCorner.topRight => Offset(maxX - m.right, m.top),
      DebugLauncherCorner.bottomLeft => Offset(m.left, maxY - m.bottom),
      DebugLauncherCorner.bottomRight => Offset(maxX - m.right, maxY - m.bottom),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    // DebugOverlay is designed to WRAP MaterialApp, so nothing above it can be
    // relied on: no Directionality, no Navigator, no Localizations, no Overlay.
    // That rules out showDialog/Navigator.push for presenting the tools — they
    // assert on exactly those. Instead the tools are rendered as a layer in our
    // own Stack, and _DebugToolsHost supplies the scopes their Material content
    // needs (including a Navigator of their own).
    //
    // Ambient values are read first, so nesting the overlay *inside* an app
    // still inherits that app's direction/locale rather than overriding it.
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;

    return Directionality(
      textDirection: textDirection,
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
          widget.child,
          if (_controller.isOpen && widget.presentation != DebugOverlayPresentation.custom)
            Positioned.fill(child: _buildTools())
          else
            Positioned.fill(child: _buildLauncher()),
        ],
      ),
    );
  }

  /// The tools, presented per [DebugOverlay.presentation]. Rendered in-tree
  /// rather than pushed as a route — see the note in [build].
  Widget _buildTools() {
    final t = widget.theme;
    final screen = DebugToolsScreen(pages: widget.pages, theme: t, onClose: _controller.close);

    final Widget presented = switch (widget.presentation) {
      DebugOverlayPresentation.fullscreen => SafeArea(child: ColoredBox(color: t.background, child: screen)),
      DebugOverlayPresentation.dialog => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              color: t.background,
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: screen,
            ),
          ),
        ),
      DebugOverlayPresentation.bottomSheet => Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.9,
            child: Material(
              color: t.background,
              elevation: 8,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(top: false, child: screen),
            ),
          ),
        ),
      DebugOverlayPresentation.custom => const SizedBox.shrink(),
    };

    // A scrim, tappable to dismiss — the stand-in for a route's modal barrier.
    // Fullscreen covers everything already, so it gets none.
    final isModal = widget.presentation != DebugOverlayPresentation.fullscreen;

    return _DebugToolsHost(
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
          if (isModal)
            Positioned.fill(
              child: GestureDetector(
                onTap: _controller.close,
                behavior: HitTestBehavior.opaque,
                child: const ColoredBox(color: Color(0x8A000000)),
              ),
            ),
          // Swallow taps on the panel itself so they don't reach the scrim.
          Positioned.fill(
            child: GestureDetector(onTap: () {}, behavior: HitTestBehavior.deferToChild, child: presented),
          ),
        ],
      ),
    );
  }

  Widget _buildLauncher() {
    return ValueListenableBuilder<bool>(
      valueListenable: _controller.showLauncher,
      builder: (context, showLauncher, _) {
        if (!showLauncher) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxX = constraints.maxWidth - widget.launcherSize;
            final maxY = constraints.maxHeight - widget.launcherSize;
            final pos = _pos ?? _defaultPos(maxX, maxY);
            final clamped = Offset(pos.dx.clamp(0.0, maxX), pos.dy.clamp(0.0, maxY));

            return Stack(
              alignment: Alignment.topLeft,
              children: [
                Positioned(
                  left: clamped.dx,
                  top: clamped.dy,
                  child: GestureDetector(
                    onTap: _controller.open,
                    onPanUpdate: (d) => setState(() {
                      final next = (_pos ?? clamped) + d.delta;
                      _pos = Offset(next.dx.clamp(0.0, maxX), next.dy.clamp(0.0, maxY));
                    }),
                    child: widget.launcherBuilder ??
                        DebugLauncherButton(
                          theme: widget.theme,
                          size: widget.launcherSize,
                          icon: widget.launcherIcon,
                          showErrorBadge: widget.showErrorBadge,
                        ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Supplies the inherited widgets the tools' Material content expects but which
/// may not exist above [DebugOverlay] — it wraps MaterialApp, so it sits outside
/// the app's Navigator/Localizations/Overlay scopes.
///
/// The [Navigator] is the important part. Material widgets inside the panel
/// reach for one constantly — `PopupMenuButton` and `showDialog` both call
/// `Navigator.of(context)`, and tooltips and text-selection handles need its
/// Overlay. Giving the panel its own means all of that works, *and* those routes
/// stay contained: a menu or dialog opened in the tools can never land on the
/// host app's route stack.
///
/// The `HzToastInitializer` is here for the same reason: the copy buttons toast,
/// and that's our business, not the host app's. Wiring it here means the host
/// needs no setup — and if the app already has its own HzToast initializer, this
/// one is nested below it and simply wins for toasts raised inside the panel.
class _DebugToolsHost extends StatelessWidget {
  final Widget child;
  const _DebugToolsHost({required this.child});

  @override
  Widget build(BuildContext context) {
    Widget content = Navigator(
      onGenerateRoute: (settings) => PageRouteBuilder<void>(
        settings: settings,
        // No transition — this is the panel itself appearing, and the overlay
        // has already animated it in.
        pageBuilder: (_, _, _) => HzToastInitializer(edgeSpacing: 32, showSingleToast: true, child: child),
      ),
    );

    // Only inject what's actually missing, so a nested overlay keeps the host
    // app's own locale and media metrics.
    if (Localizations.of<MaterialLocalizations>(context, MaterialLocalizations) == null) {
      content = Localizations(
        locale: const Locale('en', 'US'),
        delegates: const [DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
        child: content,
      );
    }

    return content;
  }
}
