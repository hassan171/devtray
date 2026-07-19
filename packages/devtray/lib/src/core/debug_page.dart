import 'package:flutter/widgets.dart';

/// One tab inside the debug tools screen.
///
/// The overlay ships with [NetworkDebugPage]; everything else is supplied by
/// the host app. Implement this (or use [DebugPage.builder]) and pass it to
/// `DevtrayOverlay(pages: [...])`.
///
/// ```dart
/// DevtrayOverlay(
///   pages: [
///     const NetworkDebugPage(),
///     DebugPage.builder(title: 'Env', builder: (_) => const MyEnvPage()),
///   ],
///   child: MaterialApp(...),
/// )
/// ```
abstract class DebugPage {
  const DebugPage();

  /// Tab label.
  String get title;

  /// Optional icon shown before the label in the tab.
  IconData? get icon => null;

  /// The tab body. Built lazily, inside the overlay's theme scope.
  Widget build(BuildContext context);

  /// Convenience factory so a page can be declared inline without a subclass.
  const factory DebugPage.builder({
    required String title,
    required WidgetBuilder builder,
    IconData? icon,
  }) = _BuilderDebugPage;
}

class _BuilderDebugPage extends DebugPage {
  @override
  final String title;
  @override
  final IconData? icon;
  final WidgetBuilder builder;

  const _BuilderDebugPage({required this.title, required this.builder, this.icon});

  @override
  Widget build(BuildContext context) => builder(context);
}
