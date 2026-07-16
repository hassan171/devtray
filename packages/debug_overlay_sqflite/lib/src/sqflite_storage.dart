import 'package:debug_overlay/debug_overlay.dart';
import 'package:sqflite/sqflite.dart';

/// Exposes a whole SQLite database to the Storage page — **hand it the `Database`
/// and it works out the rest**.
///
/// ```dart
/// StorageDebugPage(adapters: [
///   const SharedPreferencesStorageAdapter(),
///   ...await SqfliteStorage.tables(db),
/// ])
/// ```
///
/// ## Why one adapter per table
///
/// A [DebugStorageAdapter] is one flat key→value list — one entry in the store
/// list. A database has many tables, so the two don't line up one-to-one. Giving
/// each table its own adapter is what makes them fit: every table becomes a store
/// you drill into, keyed by its own primary key. The alternative — one adapter
/// for the whole database — would mean keys like `notes:1` and a `write` that has
/// to parse the table name back out of the key, which breaks the moment a key
/// contains a colon.
///
/// ## What it can and can't know
///
/// Everything here comes from SQLite's own introspection: `sqlite_master` for the
/// table list, `PRAGMA table_info` for each table's columns, types, NOT NULL
/// flags and primary key. That's enough to validate the *shape* of an edit —
/// unknown column, missing NOT NULL, wrong type — before it reaches the database,
/// so a typo is a readable message instead of a raw SQL error.
///
/// What it **cannot** know is what your data means: that `pinned` is 0/1, that
/// `status` is one of four strings, that `email` should contain an `@`. Nothing
/// in the schema says so. If those rules matter, write an adapter by hand — see
/// `NotesDbAdapter` for the same table done that way, with real validation.
///
/// Pass `writable: false` for a database you only want to read.
class SqfliteStorage {
  SqfliteStorage._();

  /// One adapter per table in [db], ready to spread into `adapters:`.
  ///
  /// Async because it has to ask the database what's in it. Internal `sqlite_*`
  /// tables are skipped — they're the engine's bookkeeping, not your data.
  static Future<List<DebugStorageAdapter>> tables(Database db, {bool writable = true}) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );

    return [
      for (final row in rows) await table(db, row['name']! as String, writable: writable),
    ];
  }

  /// A single table as an adapter, when you don't want all of them.
  static Future<DebugStorageAdapter> table(Database db, String name, {bool writable = true}) async {
    final columns = await _columnsOf(db, name);
    return _SqfliteTableAdapter(db: db, table: name, columns: columns, writable: writable);
  }

  static Future<List<_Column>> _columnsOf(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info(${_quote(table)})');
    return [
      for (final c in info)
        _Column(
          name: c['name']! as String,
          // The *declared* type. SQLite is dynamically typed, so this is a
          // convention rather than a guarantee — good enough to catch a typo,
          // not something to trust absolutely.
          declaredType: (c['type'] as String? ?? '').toUpperCase(),
          notNull: (c['notnull'] as int? ?? 0) == 1,
          hasDefault: c['dflt_value'] != null,
          isPrimaryKey: (c['pk'] as int? ?? 0) > 0,
        ),
    ];
  }

  /// Identifiers come from the database itself, so they're not attacker-controlled
  /// — but a table named `order` or `group` is a keyword, and one with a space
  /// would break the statement outright. Quoting is what makes those work.
  static String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';
}

class _Column {
  final String name;
  final String declaredType;
  final bool notNull;
  final bool hasDefault;
  final bool isPrimaryKey;

  const _Column({
    required this.name,
    required this.declaredType,
    required this.notNull,
    required this.hasDefault,
    required this.isPrimaryKey,
  });

  /// SQLite's type affinity rules, reduced to what an editor needs to check.
  bool accepts(Object? value) {
    if (value == null) return !notNull;
    if (declaredType.contains('INT')) return value is int || value is bool;
    if (declaredType.contains('REAL') || declaredType.contains('FLOA') || declaredType.contains('DOUB')) {
      return value is num;
    }
    if (declaredType.contains('CHAR') || declaredType.contains('TEXT') || declaredType.contains('CLOB')) {
      return value is String;
    }
    // BLOB, or no declared type at all: SQLite stores anything, so don't invent
    // a rule the database itself doesn't have.
    return true;
  }
}

class _SqfliteTableAdapter extends DebugStorageAdapter {
  final Database db;
  final String table;
  final List<_Column> columns;

  @override
  final bool writable;

  const _SqfliteTableAdapter({
    required this.db,
    required this.table,
    required this.columns,
    required this.writable,
  });

  @override
  String get name => '$table (SQLite)';

  /// The column identifying a row.
  ///
  /// Null for a table with no single-column primary key — a composite key, or no
  /// key at all. Those fall back to `rowid`, which SQLite gives every ordinary
  /// table for free, so a keyless table is still browsable rather than skipped.
  _Column? get _pk {
    final keys = columns.where((c) => c.isPrimaryKey).toList();
    return keys.length == 1 ? keys.single : null;
  }

  String get _keyColumn => _pk?.name ?? 'rowid';

  @override
  Future<Map<String, Object?>> readAll() async {
    final key = _keyColumn;
    // `rowid, *` when there's no declared key — `*` alone doesn't include it.
    final rows = await db.rawQuery(
      _pk == null
          ? 'SELECT rowid, * FROM ${SqfliteStorage._quote(table)} ORDER BY rowid'
          : 'SELECT * FROM ${SqfliteStorage._quote(table)} ORDER BY ${SqfliteStorage._quote(key)}',
    );

    return {
      for (final row in rows)
        row[key].toString(): {
          for (final e in row.entries)
            // The key is already the row's name — showing it inside the value
            // too invites editing one and orphaning the row.
            if (e.key != key) e.key: e.value,
        },
    };
  }

  @override
  Future<void> write(String storageKey, Object? value) async {
    if (value is! Map) {
      throw FormatException('Expected a JSON object, got ${value.runtimeType}');
    }
    final map = value.map((k, v) => MapEntry(k.toString(), v));

    // Validate against the real schema before touching the database, so a bad
    // edit is a readable message rather than a raw SQL exception surfaced from
    // three layers down.
    for (final name in map.keys) {
      if (!columns.any((c) => c.name == name)) {
        throw FormatException('No column "$name" in $table');
      }
    }

    for (final column in columns) {
      if (column.name == _keyColumn) continue; // comes from the key, not the map

      final present = map.containsKey(column.name);
      final v = map[column.name];

      // A NOT NULL column with no default has to be given something. One *with*
      // a default can be left out — SQLite fills it in.
      if (!present) {
        if (column.notNull && !column.hasDefault) {
          throw FormatException('${column.name} is NOT NULL and has no default — it must be set');
        }
        continue;
      }
      if (v == null && column.notNull) {
        throw FormatException('${column.name} is NOT NULL — it cannot be null');
      }
      if (!column.accepts(v)) {
        throw FormatException('${column.name} is ${column.declaredType} — got ${v.runtimeType}');
      }
    }

    final values = <String, Object?>{
      for (final e in map.entries)
        if (e.key != _keyColumn)
          // SQLite has no bool. The editor round-trips 0/1 as an int, but a
          // hand-typed `true` is what a person means, so coerce it.
          e.key: e.value is bool ? ((e.value! as bool) ? 1 : 0) : e.value,
    };

    // The key identifies the row, so it always wins over whatever the map says.
    final pk = _pk;
    final keyValue = pk != null && pk.declaredType.contains('INT') ? int.tryParse(storageKey) ?? storageKey : storageKey;

    final updated = await db.update(
      table,
      values,
      where: '${SqfliteStorage._quote(_keyColumn)} = ?',
      whereArgs: [keyValue],
    );

    // An UPDATE that matched nothing is a silent no-op — the page would reload
    // and show the old value with no hint why. Say so.
    if (updated == 0) {
      throw FormatException('No row with $_keyColumn = $storageKey');
    }
  }

  @override
  Future<void> delete(String storageKey) async {
    final pk = _pk;
    final keyValue = pk != null && pk.declaredType.contains('INT') ? int.tryParse(storageKey) ?? storageKey : storageKey;

    await db.delete(
      table,
      where: '${SqfliteStorage._quote(_keyColumn)} = ?',
      whereArgs: [keyValue],
    );
  }
}
