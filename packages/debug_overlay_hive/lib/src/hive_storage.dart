import 'package:debug_overlay/debug_overlay.dart';
import 'package:hive_ce/hive.dart';

/// Exposes Hive boxes to the Storage page by **registering them as you open
/// them**.
///
/// ## Why a wrapper, when SQLite needs none
///
/// SQLite is self-describing: `sqlite_master` lists the tables and
/// `PRAGMA table_info` gives every column's type — so an adapter can discover a
/// whole database with nothing but the handle. Hive can do none of that:
///
///  * **No box list.** `HiveInterface` offers `isBoxOpen(name)` and
///    `boxExists(name)` — both need the name you're trying to find. The map of
///    open boxes is private. Nothing can enumerate them.
///  * **No schema.** A box has no columns and no declared types.
///  * **No reflection.** A `Box<User>` yields `User` objects, and Dart can't turn
///    one into named fields. A generic reader would print `Instance of 'User'`.
///
/// So instead of *asking* Hive what exists, the app *declares* it — at the one
/// moment it already knows both the name and the type:
///
/// ```dart
/// // was: await Hive.openBox<String>('settings');
/// await HiveStorage.openBox<String>('settings');
/// ```
///
/// The box is returned unchanged, so it's a drop-in. Registration is the side
/// effect.
///
/// ## Typed boxes
///
/// A box of primitives needs nothing more — the values are already showable and
/// editable. A box of *your* objects needs one thing Hive can't supply: how to
/// turn the object into named fields, and back.
///
/// ```dart
/// await HiveStorage.openBox<User>(
///   'users',
///   toMap: (u) => u.toMap(),
///   fromMap: (key, map) => User.fromMap(map),   // omit for read-only
/// );
/// ```
///
/// Without `toMap` a typed box is registered **read-only** and its values are
/// shown as `toString()` — browsable, honest about being un-editable, rather
/// than pretending an edit would work.
class HiveStorage {
  HiveStorage._();

  /// Every box registered so far, in the order they were opened.
  ///
  /// Spread into `adapters:` — or pass the list by reference if the page is
  /// built before the boxes are open (see the example's `main.dart`).
  static final List<DebugStorageAdapter> boxes = [];

  /// [Hive.openBox], plus registration. Returns the same box Hive does.
  ///
  /// [toMap] turns a value into named fields for the editor; [fromMap] turns the
  /// edited fields back into a value. Neither is needed for a box of primitives.
  /// With [toMap] but no [fromMap] the box is registered read-only — showing an
  /// edit control that can't write would be a lie.
  static Future<Box<E>> openBox<E>(
    String name, {
    Map<String, Object?> Function(E value)? toMap,
    E Function(String key, Map<String, Object?> map)? fromMap,
    String? label,
    bool writable = true,
    HiveCipher? encryptionCipher,
  }) async {
    final box = await Hive.openBox<E>(name, encryptionCipher: encryptionCipher);
    register<E>(box, toMap: toMap, fromMap: fromMap, label: label, writable: writable);
    return box;
  }

  /// Registers a box that's already open — for a box opened elsewhere, or one
  /// you don't control the opening of.
  ///
  /// Registering the same box twice is a no-op. That's not paranoia: Hive's
  /// `openBox` **returns the existing instance if the box is already open**, so
  /// a second `HiveStorage.openBox('users')` — from a retried bootstrap, a hot
  /// restart, or two call sites that both want the box — succeeds silently and
  /// would otherwise put the same store in the list twice.
  static void register<E>(
    Box<E> box, {
    Map<String, Object?> Function(E value)? toMap,
    E Function(String key, Map<String, Object?> map)? fromMap,
    String? label,
    bool writable = true,
  }) {
    // Keyed on the box's name, which is Hive's own identity for it — not the
    // label, which is cosmetic and may differ between call sites.
    if (isRegistered(box.name)) return;

    boxes.add(
      _HiveBoxAdapter<E>(
        box: box,
        label: label ?? '${box.name} (Hive)',
        toMap: toMap,
        fromMap: fromMap,
        allowWrites: writable,
      ),
    );
  }

  /// Whether a box of this name is already registered.
  ///
  /// Hive lowercases box names internally, so the comparison does too — `Users`
  /// and `users` are the same box to Hive, and must be here as well.
  static bool isRegistered(String boxName) {
    final target = boxName.toLowerCase();
    return boxes.any((a) => a is _HiveBoxAdapter && a.box.name.toLowerCase() == target);
  }

  /// Forget every registration — for tests, so one test's boxes don't leak into
  /// the next.
  static void reset() => boxes.clear();
}

class _HiveBoxAdapter<E> extends DebugStorageAdapter {
  final Box<E> box;
  final String label;
  final Map<String, Object?> Function(E value)? toMap;
  final E Function(String key, Map<String, Object?> map)? fromMap;

  /// What the caller asked for. Whether it's actually *possible* is [writable].
  final bool allowWrites;

  const _HiveBoxAdapter({
    required this.box,
    required this.label,
    required this.toMap,
    required this.fromMap,
    required this.allowWrites,
  });

  @override
  String get name => label;

  /// Editable only if an edit can be turned back into a value:
  ///
  ///  * **primitives** — the editor's output *is* the value;
  ///  * **typed + [fromMap]** — the app rebuilds it;
  ///  * **typed, no [fromMap]** — nothing can. Dart has no reflection, so there
  ///    is no route from the text on screen back to a `User`. Read-only whatever
  ///    the caller asked for; an edit control that can't write is a lie.
  @override
  bool get writable => allowWrites && (_isPrimitive || fromMap != null);

  /// True when the box holds plain values the page can already render and edit.
  ///
  /// `Box<dynamic>` — the default when you call `openBox('x')` with no type — is
  /// included: its values are whatever was put in, which for the overwhelmingly
  /// common case is primitives.
  bool get _isPrimitive => const [
        dynamic,
        String,
        int,
        double,
        bool,
        num,
        List<String>,
        Map<String, dynamic>,
      ].contains(E);

  @override
  Future<Map<String, Object?>> readAll() async {
    return {
      for (final key in box.keys)
        key.toString(): switch (box.get(key)) {
          // A typed box, with a converter: named fields, so it edits as JSON.
          final E v when toMap != null => toMap!(v),
          // A box of primitives: already showable as-is.
          final v when _isPrimitive => v,
          // A typed box with no converter. `toString()` is all Dart can offer
          // without reflection — enough to browse, and the adapter is read-only
          // so nothing pretends otherwise.
          final v => v?.toString(),
        },
    };
  }

  @override
  Future<void> write(String key, Object? value) async {
    final convert = fromMap;

    if (convert != null) {
      if (value is! Map) {
        throw FormatException('Expected a JSON object, got ${value.runtimeType}');
      }
      // Rebuild through the app's own constructor rather than trusting the map —
      // a missing or wrong-typed field fails here, not later when something
      // reads the box.
      final map = value.map((k, v) => MapEntry(k.toString(), v));
      await box.put(key, convert(key, map));
      return;
    }

    if (value is! E) {
      throw FormatException('$label holds $E — got ${value.runtimeType}');
    }
    await box.put(key, value);
  }

  @override
  Future<void> delete(String key) => box.delete(key);
}
