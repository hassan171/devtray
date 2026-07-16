import 'package:flutter/material.dart';

/// Colors used across the overlay. Every value has a sane default, so the
/// host app can drop the overlay in with zero configuration and still restyle
/// any single color later without forking the widgets.
class DevtrayTheme {
  final Color background;
  final Color surface;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color success;
  final Color warning;
  final Color error;
  final Color launcherBackground;
  final Color launcherIcon;

  const DevtrayTheme({
    this.background = Colors.white,
    this.surface = const Color(0xFFF2F3F5),
    this.border = const Color(0xFFDDDFE3),
    this.text = const Color(0xFF1F2229),
    this.textMuted = const Color(0xFF878C96),
    this.accent = const Color(0xFF2D7FF9),
    this.success = const Color(0xFF2BB673),
    this.warning = const Color(0xFFF2994A),
    this.error = const Color(0xFFE5484D),
    this.launcherBackground = const Color(0xE61F2229),
    this.launcherIcon = Colors.white,
  });

  /// A dark preset, for apps whose debug builds run on a dark theme.
  const DevtrayTheme.dark()
      : background = const Color(0xFF16181D),
        surface = const Color(0xFF23262D),
        border = const Color(0xFF33373F),
        text = const Color(0xFFECEDEF),
        textMuted = const Color(0xFF878C96),
        accent = const Color(0xFF5B9DFF),
        success = const Color(0xFF3DD68C),
        warning = const Color(0xFFF2994A),
        error = const Color(0xFFFF6369),
        launcherBackground = const Color(0xE6ECEDEF),
        launcherIcon = const Color(0xFF16181D);

  /// Nearest enclosing theme, or the light default when the overlay is used
  /// outside a [DevtrayThemeScope] (e.g. a page rendered standalone).
  static DevtrayTheme of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DevtrayThemeScope>()?.theme ?? const DevtrayTheme();
  }
}

class DevtrayThemeScope extends InheritedWidget {
  final DevtrayTheme theme;

  const DevtrayThemeScope({super.key, required this.theme, required super.child});

  @override
  bool updateShouldNotify(DevtrayThemeScope oldWidget) => theme != oldWidget.theme;
}
