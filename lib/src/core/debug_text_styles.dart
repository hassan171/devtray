import 'package:flutter/material.dart';

/// Typography for the overlay.
///
/// The overlay shows **data** — URLs, status codes, durations, payloads, keys.
/// Rendering those in a proportional font is what makes a debug tool read like a
/// settings form: glyph widths jitter as values change, columns fail to line up,
/// and `l`/`1`/`I` blur together in a header dump.
///
/// So anything machine-produced uses [debugMono]. Anything a human reads as
/// prose (labels, empty states, section titles) stays in the platform's default
/// UI font. That split is the whole rule.
class DebugTextStyles {
  DebugTextStyles._();

  /// The bundled monospace family — JetBrains Mono, shipped with the package.
  ///
  /// Bundled rather than named-and-hoped-for: a system stack
  /// (`SF Mono`/`Consolas`/`monospace`) renders differently on every platform
  /// and silently falls back to a *proportional* font where none match, which
  /// defeats the point. Shipping it means the columns line up everywhere, with
  /// no setup in the host app.
  static const String monoFamily = 'JetBrainsMono';

  /// The font lives in this package, so it must be resolved against it — a bare
  /// family name would only find a font the *host app* declared.
  static const String _package = 'debug_overlay';

  /// Monospace, with **tabular figures**.
  ///
  /// `tnum` fixes every digit to the same advance width, so a duration ticking
  /// 9ms → 10ms → 100ms doesn't shift the column, and status codes stack into a
  /// readable edge. Without it, right-aligned numbers visibly wobble on every
  /// update — the kind of jitter that reads as "unpolished" without the viewer
  /// being able to name why.
  static TextStyle debugMono({
    required Color color,
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: monoFamily,
      package: _package,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// Uppercase micro-type for badges and section headers.
  ///
  /// Mono like the data it labels — a `GET` badge sitting above a mono URL is
  /// part of the same machine-readable column, and mixing a proportional font
  /// in at 10px makes the two look accidentally different rather than
  /// deliberately distinct. The tracking is what keeps it legible that small.
  static TextStyle label({
    required Color color,
    double fontSize = 10,
    FontWeight fontWeight = FontWeight.w700,
    double letterSpacing = 0.6,
  }) {
    return TextStyle(
      fontFamily: monoFamily,
      package: _package,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }
}
