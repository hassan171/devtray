import 'dart:io';
import 'dart:math';

import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A tiny SQLite table, to show [DebugStorageAdapter] against a **relational**
/// store rather than another key/value one.
///
/// That's the point of including it: SharedPreferences and Hive are both already
/// maps, so an adapter over them proves very little. A SQL table isn't a map at
/// all — it has a schema, typed columns and a primary key — and the adapter has
/// to decide what a "key" and a "value" even mean before the Storage page can
/// show it. It can, because the interface only asks for three methods.
class NotesDb {
  static const _table = 'notes';
  static Database? _db;

  static Database get db => _db!;

  /// Opens the database, creating the table and seeding a few rows.
  ///
  /// `sqflite` ships native implementations for Android/iOS/macOS only. On
  /// Windows and Linux it has no plugin, so the example would crash on the
  /// desktop it's most often run on — `sqflite_common_ffi` supplies those, and
  /// initialising it is a no-op for the platforms sqflite already handles.
  static Future<void> init() async {
    if (kIsWeb) return; // no sqlite on web without extra setup — skip it
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _db = await databaseFactory.openDatabase(
      // A file path on desktop, the app's db dir elsewhere; inMemory keeps the
      // example from leaving anything behind.
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          // Several tables of deliberately different shapes, so the auto-
          // discovered store list has something real to show — and so the
          // generic adapter's schema validation is exercised against more than
          // one kind of table.
          await db.execute('''
            CREATE TABLE $_table (
              id INTEGER PRIMARY KEY,
              title TEXT NOT NULL,
              body TEXT NOT NULL,
              pinned INTEGER NOT NULL DEFAULT 0
            )
          ''');

          // A TEXT primary key, not an INTEGER one.
          await db.execute('''
            CREATE TABLE tags (
              name TEXT PRIMARY KEY,
              colour TEXT NOT NULL,
              uses INTEGER NOT NULL DEFAULT 0
            )
          ''');

          // REAL and nullable columns.
          await db.execute('''
            CREATE TABLE events (
              id INTEGER PRIMARY KEY,
              kind TEXT NOT NULL,
              duration_ms REAL,
              ok INTEGER NOT NULL DEFAULT 1,
              note TEXT
            )
          ''');

          // NO primary key at all — SQLite still gives it a rowid, and the
          // generic adapter falls back to that rather than skipping the table.
          await db.execute('CREATE TABLE migrations (version TEXT NOT NULL, applied_at TEXT NOT NULL)');
        },
      ),
    );

    await seed();
  }

  /// Fills the tables with plausible-looking rows.
  ///
  /// Deterministic — a fixed seed, not `Random()`. A demo whose data changes on
  /// every launch makes "did my edit save?" impossible to answer at a glance.
  static Future<void> seed() async {
    final existing = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $_table')) ?? 0;
    if (existing > 0) return;

    final rng = Random(42);
    final batch = db.batch();

    const words = ['sync', 'cache', 'retry', 'draft', 'archive', 'pinned', 'inbox', 'review'];
    for (var i = 1; i <= 12; i++) {
      batch.insert(_table, {
        'id': i,
        'title': '${words[rng.nextInt(words.length)]} note $i',
        'body': 'The body of note $i. Edit me from the Storage page.',
        'pinned': i % 4 == 0 ? 1 : 0,
      });
    }

    const tags = {'flutter': 'blue', 'dart': 'teal', 'bug': 'red', 'chore': 'grey', 'design': 'purple'};
    for (final e in tags.entries) {
      batch.insert('tags', {'name': e.key, 'colour': e.value, 'uses': rng.nextInt(40)});
    }

    const kinds = ['app_start', 'login', 'fetch_users', 'sync', 'logout'];
    for (var i = 1; i <= 15; i++) {
      final ok = rng.nextInt(10) > 1;
      batch.insert('events', {
        'id': i,
        'kind': kinds[rng.nextInt(kinds.length)],
        // Nullable on purpose — a null here is worth seeing in the editor.
        'duration_ms': rng.nextBool() ? (rng.nextDouble() * 800).roundToDouble() / 10 : null,
        'ok': ok ? 1 : 0,
        'note': ok ? null : 'failed after ${rng.nextInt(3) + 1} retries',
      });
    }

    for (var i = 1; i <= 4; i++) {
      batch.insert('migrations', {
        'version': '2024.0$i',
        'applied_at': '2024-0$i-1${rng.nextInt(9)}T09:${rng.nextInt(6)}0:00Z',
      });
    }

    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, Object?>>> rows() => db.query(_table, orderBy: 'id');

  static Future<void> upsert(int id, Map<String, Object?> values) async {
    await db.insert(
      _table,
      {...values, 'id': id},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deleteRow(int id) async => db.delete(_table, where: 'id = ?', whereArgs: [id]);
}

/// Exposes the `notes` table to the Storage page.
///
/// The mapping a relational store needs, and why:
///
///  * **key** — the row's primary key, as a string. A SQL table has no "keys",
///    so the adapter picks the thing that identifies a row. Anything else (a
///    row index, say) would break the moment rows were reordered or deleted.
///  * **value** — the rest of the row as a map, so the Storage page renders it
///    as JSON with every column named, and an edit is `"pinned": 1` rather than
///    re-typing a summary line.
///  * **delete** — a real `DELETE`, so the page's confirmation is guarding an
///    actual irreversible statement.
///
/// The `id` is deliberately stripped from the value: it's already the key, and
/// showing it twice invites you to edit one and orphan the row. [write] puts it
/// back from the key, so renaming it in the editor can't do damage.
class NotesDbAdapter extends DebugStorageAdapter {
  @override
  String get name => 'Notes (SQLite)';

  @override
  Future<Map<String, Object?>> readAll() async {
    final rows = await NotesDb.rows();
    return {
      for (final row in rows)
        row['id'].toString(): {
          for (final e in row.entries)
            if (e.key != 'id') e.key: e.value,
        },
    };
  }

  @override
  Future<void> write(String key, Object? value) async {
    if (value is! Map) {
      throw FormatException('Expected a JSON object, got ${value.runtimeType}');
    }

    final id = int.tryParse(key);
    if (id == null) throw FormatException('Not a row id: $key');

    // Validate against the schema here rather than letting SQLite throw on the
    // INSERT — the error is far more readable, and a NOT NULL violation surfaced
    // from a debug tool should say which column.
    final map = value.map((k, v) => MapEntry(k.toString(), v));
    for (final column in ['title', 'body', 'pinned']) {
      if (!map.containsKey(column)) throw FormatException('Missing column: $column');
    }
    if (map['title'] is! String) throw const FormatException('title must be a string');
    if (map['body'] is! String) throw const FormatException('body must be a string');
    // SQLite has no bool — pinned is an INTEGER 0/1, and the editor round-trips
    // it as a number. Accept a bool too, since that's what someone will type.
    final pinned = map['pinned'];
    final pinnedInt = switch (pinned) {
      final bool b => b ? 1 : 0,
      final int i => i,
      _ => throw const FormatException('pinned must be 0 or 1'),
    };

    await NotesDb.upsert(id, {'title': map['title'], 'body': map['body'], 'pinned': pinnedInt});
  }

  @override
  Future<void> delete(String key) async {
    final id = int.tryParse(key);
    if (id == null) return;
    await NotesDb.deleteRow(id);
  }
}
