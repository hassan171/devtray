import 'package:shared_preferences/shared_preferences.dart';

import 'debug_storage_adapter.dart';

/// Browse and edit `SharedPreferences`. Built in — the package already depends
/// on it for mock-rule persistence, so this costs nothing extra.
class SharedPreferencesStorageAdapter extends DebugStorageAdapter {
  @override
  final String name;

  /// Hide the overlay's own keys, which are noise you never want to edit.
  final bool hideInternalKeys;

  const SharedPreferencesStorageAdapter({
    this.name = 'SharedPreferences',
    this.hideInternalKeys = true,
  });

  @override
  Future<Map<String, Object?>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => !hideInternalKeys || !k.startsWith('debug_overlay.'));
    return {for (final k in keys) k: prefs.get(k)};
  }

  @override
  Future<void> write(String key, Object? value) async {
    final prefs = await SharedPreferences.getInstance();

    // SharedPreferences has no generic setter — it's one method per type, and
    // the value must match the type already stored or the next read throws.
    // The editor preserves the original type, so this switch always has a match.
    switch (value) {
      case final bool v:
        await prefs.setBool(key, v);
      case final int v:
        await prefs.setInt(key, v);
      case final double v:
        await prefs.setDouble(key, v);
      case final String v:
        await prefs.setString(key, v);
      case final List<String> v:
        await prefs.setStringList(key, v);
      case null:
        await prefs.remove(key);
      default:
        throw ArgumentError('SharedPreferences cannot store ${value.runtimeType}');
    }
  }

  @override
  Future<void> delete(String key) async {
    await (await SharedPreferences.getInstance()).remove(key);
  }
}
