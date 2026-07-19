import 'package:flutter/foundation.dart';

/// Drives the overlay from anywhere — a shake detector, a secret 5-tap gesture,
/// a hidden menu item, a keyboard shortcut, a test.
///
/// ```dart
/// final debug = DevtrayController();
///
/// DevtrayOverlay(controller: debug, pages: [...], child: MaterialApp(...));
///
/// // …anywhere later:
/// debug.open();
/// ```
///
/// Also controls whether the floating launcher button is visible:
/// `debug.showLauncher.value = false` hides it while leaving `open()` working,
/// which is how you build an app with no visible debug affordance at all.
class DevtrayController extends ChangeNotifier {
  final ValueNotifier<bool> _isOpen = ValueNotifier(false);

  /// Whether the floating launcher button is rendered. Flip it at runtime to
  /// gate the button behind a setting, a build flavor, a login role…
  final ValueNotifier<bool> showLauncher;

  DevtrayController({bool showLauncher = true}) : showLauncher = ValueNotifier(showLauncher);

  ValueListenable<bool> get isOpenListenable => _isOpen;
  bool get isOpen => _isOpen.value;

  void open() {
    if (_isOpen.value) return;
    _isOpen.value = true;
    notifyListeners();
  }

  void close() {
    if (!_isOpen.value) return;
    _isOpen.value = false;
    notifyListeners();
  }

  void toggle() => _isOpen.value ? close() : open();

  @override
  void dispose() {
    _isOpen.dispose();
    showLauncher.dispose();
    super.dispose();
  }
}
