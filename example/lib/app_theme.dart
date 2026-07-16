import 'package:flutter/material.dart';

/// The example app's own look — warm ink and amber on cream.
///
/// Deliberately **nothing like** the overlay's blue/grey. The overlay sits on
/// top of a host app, and the two should never be mistaken for each other: if
/// the demo app shared the tool's palette, screenshots of this example would
/// teach the wrong thing about where the package ends and your app begins.
///
/// Flat: no gradients, no elevation games — the notes are the content, the
/// chrome gets out of the way.
class AppTheme {
  AppTheme._();

  static const _amber = Color(0xFFD97706);
  static const _cream = Color(0xFFFFFBEB);
  static const _ink = Color(0xFF1C1917);

  static ThemeData light() => _build(
        brightness: Brightness.light,
        background: _cream,
        surface: Colors.white,
        onSurface: _ink,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        background: const Color(0xFF1C1917),
        surface: const Color(0xFF292524),
        onSurface: const Color(0xFFF5F5F4),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color onSurface,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _amber,
      brightness: brightness,
    ).copyWith(surface: background, onSurface: onSurface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      // A flat app bar that reads as part of the page, not a floating band.
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: onSurface, letterSpacing: -0.3),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: _amber.withValues(alpha: 0.18),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _amber, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
    );
  }
}
