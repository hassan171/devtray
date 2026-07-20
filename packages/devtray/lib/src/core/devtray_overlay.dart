import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'debug_launcher_button.dart';
import 'devtray_facade.dart';
import 'devtray_theme.dart';
import 'debug_page.dart';
import 'debug_tools_screen.dart';

/// How the tools are presented when opened.
///
/// These are drawn as a layer inside the overlay's own Stack, not pushed onto
/// your Navigator — so opening the tools never touches your app's route stack,
/// and back/pop behaviour in your app is unaffected.
enum DevtrayPresentation {
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
/// DevtrayOverlay(
///   enabled: kDebugMode,                       // when it exists at all
///   showLauncher: true,                        // whether the button is drawn
///   presentation: DevtrayPresentation.dialog,
///   theme: const DevtrayTheme.dark(),
///   pages: [
///     const NetworkDebugPage(),
///     DebugPage.builder(title: 'Env', builder: (_) => const MyEnvPage()),
///   ],
///   child: MaterialApp(...),
/// )
/// ```
///
/// With `showLauncher: false` there is no visible affordance at all — call
/// [Devtray.open] from your own trigger (shake, 5-tap on the logo, a hidden
/// settings row).
///
/// Opening and closing live on [Devtray] rather than on a controller you inject,
/// because a process has one panel. That also removes a duplication this widget
/// used to carry: `showLauncher` existed here, on [runDebugApp] *and* on the
/// controller, and this one was silently ignored whenever a controller was
/// supplied.
class DevtrayOverlay extends StatefulWidget {
  /// The app. The overlay is stacked on top of it.
  final Widget child;

  /// The tabs. Order is preserved.
  final List<DebugPage> pages;

  /// Master switch for the *UI*. When false the overlay renders nothing and
  /// never captures gestures — pass an env flag, a remote flag, whatever.
  ///
  /// Defaults to [kDebugMode], matching [Devtray.enabled]: the stores already
  /// refuse to record in release, so defaulting this to `true` meant the one
  /// thing that *did* survive into production was the floating bug button. Pass
  /// `true` explicitly if you want the tools in a release build (a staging or
  /// dogfood flavour).
  ///
  /// This is the UI half only. [Devtray.enabled] is the capture half, and they
  /// are separate because a staging build reasonably wants capture on with no
  /// visible affordance.
  final bool enabled;

  /// The launcher's default visibility.
  ///
  /// A default, not the source of truth: `configure: (d) => d..launcher(...)`
  /// and assigning `Devtray.showLauncher` both override it, whenever they run.
  final bool showLauncher;

  final DevtrayPresentation presentation;
  final DevtrayTheme theme;

  /// Starting corner of the launcher button. It stays draggable from there.
  final DebugLauncherCorner launcherCorner;
  final EdgeInsets launcherMargin;
  final double launcherSize;
  final IconData launcherIcon;

  /// Show a red count badge on the launcher when errors have been captured but
  /// not yet reviewed. Requires [captureErrors] (which [runDebugApp] installs) to
  /// be installed, and is ignored when [launcherBuilder] replaces the button.
  final bool showErrorBadge;

  /// Replaces the default bug button entirely. It's still positioned and
  /// draggable — you only supply the visuals.
  final Widget? launcherBuilder;

  const DevtrayOverlay({
    super.key,
    required this.child,
    this.pages = const [],
    this.enabled = kDebugMode,
    this.showLauncher = true,
    this.presentation = DevtrayPresentation.dialog,
    this.theme = const DevtrayTheme(),
    this.launcherCorner = DebugLauncherCorner.bottomRight,
    this.launcherMargin = const EdgeInsets.all(16),
    this.launcherSize = 48,
    this.launcherIcon = Icons.bug_report,
    this.showErrorBadge = true,
    this.launcherBuilder,
  });

  @override
  State<DevtrayOverlay> createState() => _DevtrayState();
}

class _DevtrayState extends State<DevtrayOverlay> {
  @override
  void initState() {
    super.initState();
    // Seed, not own. This widget's argument is a default; anything that set
    // Devtray.showLauncher on purpose — `configure: ..launcher(false)`, or a
    // runtime assignment — wins, because the overlay mounts after configure has
    // already run and would otherwise silently undo it.
    Devtray.seedShowLauncher(widget.showLauncher);
  }

  /// Where the launcher sits. Null until first drag — the button then stays
  /// wherever it was dropped.
  ///
  /// A [ValueNotifier] rather than plain state on purpose: dragging fires on
  /// every pointer move, and `setState` here would rebuild this widget — whose
  /// child is the entire host app. Driving the position through a listenable
  /// scoped to the [Positioned] keeps the app out of the drag path entirely.
  final ValueNotifier<Offset?> _pos = ValueNotifier<Offset?>(null);

  @override
  void didUpdateWidget(DevtrayOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the seed itself changes. Re-applying on every rebuild would
    // stomp a runtime `Devtray.showLauncher = false` the moment anything above
    // this widget rebuilt.
    if (oldWidget.showLauncher != widget.showLauncher) {
      Devtray.seedShowLauncher(widget.showLauncher);
    }
  }

  @override
  void dispose() {
    // Devtray's notifiers are process-global and outlive this widget — see
    // Devtray.reset. Only what this State owns gets disposed.
    _pos.dispose();
    super.dispose();
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

    // Devtray is designed to WRAP MaterialApp, so nothing above it can be
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
          // The host app is a direct child of the Stack — never inside a
          // builder — so no overlay state change can rebuild it. The
          // RepaintBoundary is the other half of that guarantee: without it the
          // app and the overlay share one paint layer, and a moving launcher
          // (or a badge count changing) repaints the whole app with it.
          RepaintBoundary(child: widget.child),
          // Only this layer reacts to open/close. Its own RepaintBoundary keeps
          // overlay repaints from dirtying the app's layer.
          Positioned.fill(
            child: RepaintBoundary(
              child: ValueListenableBuilder<bool>(
                valueListenable: Devtray.isOpenListenable,
                builder: (context, isOpen, _) {
                  if (isOpen && widget.presentation != DevtrayPresentation.custom) return _buildTools();
                  return _buildLauncher();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The tools, presented per [Devtray.presentation]. Rendered in-tree
  /// rather than pushed as a route — see the note in [build].
  Widget _buildTools() {
    final t = widget.theme;
    final screen = DebugToolsScreen(pages: widget.pages, theme: t, onClose: Devtray.close);

    final Widget presented = switch (widget.presentation) {
      DevtrayPresentation.fullscreen => SafeArea(child: ColoredBox(color: t.background, child: screen)),
      DevtrayPresentation.dialog => Center(
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
      DevtrayPresentation.bottomSheet => Align(
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
      DevtrayPresentation.custom => const SizedBox.shrink(),
    };

    // A scrim, tappable to dismiss — the stand-in for a route's modal barrier.
    // Fullscreen covers everything already, so it gets none.
    final isModal = widget.presentation != DevtrayPresentation.fullscreen;

    return _DebugToolsHost(
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
          if (isModal)
            Positioned.fill(
              child: GestureDetector(
                onTap: Devtray.close,
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
      valueListenable: Devtray.showLauncherListenable,
      builder: (context, showLauncher, _) {
        if (!showLauncher) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) {
            final maxX = constraints.maxWidth - widget.launcherSize;
            final maxY = constraints.maxHeight - widget.launcherSize;

            // Built once per layout, not once per pointer move — the button
            // itself is identical at every drag position, so hoisting it out of
            // the builder below means dragging only re-runs `Positioned`.
            final button = GestureDetector(
              onTap: Devtray.open,
              onPanUpdate: (d) {
                final current = _pos.value ?? _defaultPos(maxX, maxY);
                final next = current + d.delta;
                _pos.value = Offset(next.dx.clamp(0.0, maxX), next.dy.clamp(0.0, maxY));
              },
              child: widget.launcherBuilder ??
                  DebugLauncherButton(
                    theme: widget.theme,
                    size: widget.launcherSize,
                    icon: widget.launcherIcon,
                    showErrorBadge: widget.showErrorBadge,
                  ),
            );

            return ValueListenableBuilder<Offset?>(
              valueListenable: _pos,
              child: RepaintBoundary(child: button),
              builder: (context, pos, child) {
                final resolved = pos ?? _defaultPos(maxX, maxY);
                final clamped = Offset(resolved.dx.clamp(0.0, maxX), resolved.dy.clamp(0.0, maxY));

                return Stack(
                  alignment: Alignment.topLeft,
                  children: [
                    Positioned(left: clamped.dx, top: clamped.dy, child: child!),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Supplies the inherited widgets the tools' Material content expects but which
/// may not exist above [Devtray] — it wraps MaterialApp, so it sits outside
/// the app's Navigator/Localizations/Overlay scopes.
///
/// The [Navigator] is the important part. Material widgets inside the panel
/// reach for one constantly — `PopupMenuButton` and `showDialog` both call
/// `Navigator.of(context)`, and tooltips and text-selection handles need its
/// Overlay. Giving the panel its own means all of that works, *and* those routes
/// stay contained: a menu or dialog opened in the tools can never land on the
/// host app's route stack.
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
        pageBuilder: (_, _, _) => child,
      ),
    );

    // Text fields need more than a Navigator.
    //
    // Typing a character goes through the platform text-input channel and works
    // anywhere. But backspace, the arrow keys, select-all and friends are
    // *key bindings* — they're resolved by the Shortcuts/Actions pair that
    // WidgetsApp installs. This panel is rendered ABOVE MaterialApp, so it sits
    // outside that scope: without this you can type into a field but not delete
    // or navigate within it.
    //
    // This mirrors WidgetsApp's own stack (see WidgetsApp.build): Shortcuts →
    // DefaultTextEditingShortcuts → Actions → FocusTraversalGroup →
    // TapRegionSurface. DefaultTextEditingShortcuts is nested *inside* Shortcuts
    // so it can fall through to the defaults, and TapRegionSurface is what makes
    // tapping outside a field dismiss its focus.
    content = Shortcuts(
      debugLabel: '<devtray tools shortcuts>',
      shortcuts: WidgetsApp.defaultShortcuts,
      child: DefaultTextEditingShortcuts(
        child: Actions(
          actions: WidgetsApp.defaultActions,
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: TapRegionSurface(child: content),
          ),
        ),
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
