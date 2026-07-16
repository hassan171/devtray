/// SQLite support for `devtray`'s Storage page.
///
/// Hand it the `Database` and it works out the rest — every table becomes a
/// store you can browse and edit:
///
/// ```dart
/// StorageDebugPage(adapters: [
///   ...await SqfliteStorage.tables(db),
/// ])
/// ```
///
/// It can do that because **SQLite describes itself**: `sqlite_master` lists the
/// tables, `PRAGMA table_info` gives each one's columns, declared types, NOT NULL
/// flags and primary key. That's enough to validate the *shape* of an edit —
/// unknown column, missing NOT NULL, wrong type — before it reaches the
/// database, so a typo is a readable message instead of a raw SQL error.
///
/// What it **cannot** know is what your data means: that `pinned` is 0/1, that
/// `status` is one of four strings. No schema says so. When those rules matter,
/// write a `DebugStorageAdapter` by hand — the example has one for the same
/// table, for comparison.
///
/// Pass `writable: false` for a database you only want to read.
library;

export 'src/sqflite_storage.dart';
