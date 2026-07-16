/// Hive support for `debug_overlay`'s Storage page.
///
/// Swap `Hive.openBox` for `HiveStorage.openBox` and the box shows up on the
/// Storage page. The box comes back unchanged, so it's a drop-in:
///
/// ```dart
/// // was: await Hive.openBox<String>('settings');
/// await HiveStorage.openBox<String>('settings');
///
/// StorageDebugPage(adapters: HiveStorage.boxes)
/// ```
///
/// ## Why a wrapper, when SQLite needs none
///
/// `debug_overlay_sqflite` discovers a whole database from the handle alone,
/// because SQLite describes itself. Hive can do none of that:
///
///  * **No box list.** `HiveInterface` offers `isBoxOpen(name)` and
///    `boxExists(name)` — both need the name you're looking for. The map of open
///    boxes is private. Nothing can enumerate them.
///  * **No schema.** A box has no columns and no declared types.
///  * **No reflection.** A `Box<User>` yields `User` objects, and Dart can't turn
///    one into named fields. A generic reader would print `Instance of 'User'`.
///
/// So rather than *asking* Hive what exists, the app *declares* it — at the one
/// moment it already knows both the name and the type.
///
/// A box of primitives needs nothing more. A box of your own objects needs the
/// one thing Hive can't supply: how to turn the object into named fields and
/// back.
///
/// ```dart
/// await HiveStorage.openBox<User>(
///   'users',
///   toMap: (u) => u.toMap(),
///   fromMap: (key, map) => User.fromMap(int.parse(key), map),
/// );
/// ```
///
/// Without `fromMap` a typed box is registered **read-only** — there's no route
/// from the text on screen back to a `User`, and an edit control that can't
/// write is a lie.
library;

export 'src/hive_storage.dart';
