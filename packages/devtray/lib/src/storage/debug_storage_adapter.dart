/// A key/value store the Storage page can browse and edit.
///
/// Ship your own for Hive, secure storage, an in-memory cache — anything with
/// keys and values. [SharedPreferencesStorageAdapter] is built in.
///
/// ```dart
/// class MyHiveAdapter extends DebugStorageAdapter {
///   @override
///   String get name => 'Settings';
///
///   @override
///   Future<Map<String, Object?>> readAll() async {
///     final box = Hive.box<String>('settings');
///     return {for (final k in box.keys) k.toString(): box.get(k)};
///   }
///
///   @override
///   Future<void> write(String key, Object? value) async =>
///       Hive.box<String>('settings').put(key, value as String);
///
///   @override
///   Future<void> delete(String key) async => Hive.box<String>('settings').delete(key);
/// }
/// ```
abstract class DebugStorageAdapter {
  const DebugStorageAdapter();

  /// Section label on the page.
  String get name;

  /// Every key/value pair, read fresh each time the page refreshes.
  Future<Map<String, Object?>> readAll();

  /// Persist a value. Only called when the page's edit lock is open.
  ///
  /// The value's runtime type is whatever the editor produced — it preserves the
  /// existing value's type (a `bool` stays a `bool`, an `int` stays an `int`), so
  /// a store that cares about types can cast safely.
  Future<void> write(String key, Object? value);

  /// Remove a key entirely.
  Future<void> delete(String key);

  /// Set false for stores you only want to look at. The page hides its edit and
  /// delete controls for this section.
  bool get writable => true;

  /// A caveat about what [readAll] just returned, shown above the list.
  ///
  /// For anything that makes the view less than the whole truth — most obviously
  /// a row cap. A store that quietly returns a subset reads as complete, and
  /// "the key isn't there" is then indistinguishable from "the key is past the
  /// limit". Read after [readAll]; null when there's nothing to say.
  String? get notice => null;
}

class DebugStorageAdapterInLine extends DebugStorageAdapter {
  final String _name;
  final Future<Map<String, Object?>> Function() _readAll;
  final Future<void> Function(String key, Object? value) _write;
  final Future<void> Function(String key) _delete;
  final bool _writable;

  DebugStorageAdapterInLine({required this._name, required this._readAll, required this._write, required this._delete, this._writable = true});

  @override
  String get name => _name;

  @override
  Future<Map<String, Object?>> readAll() => _readAll();

  @override
  Future<void> write(String key, Object? value) => _write(key, value);

  @override
  Future<void> delete(String key) => _delete(key);

  @override
  bool get writable => _writable;
}
