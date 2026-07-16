// The generic SQLite adapter discovers everything from the database itself, so
// the only way to know it works is to point it at real schemas — including the
// awkward ones (no primary key, a keyword for a name, a text key).
import 'package:debug_overlay_sqflite/debug_overlay_sqflite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

late Database db;

Future<void> _open() async {
  db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  await db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT NOT NULL, pinned INTEGER DEFAULT 0)');
  await db.execute('CREATE TABLE tags (name TEXT PRIMARY KEY, color TEXT)');
  // No primary key at all — SQLite still gives it a rowid.
  await db.execute('CREATE TABLE plain (a TEXT, b TEXT)');
  // A reserved word as a table name: only works if identifiers are quoted.
  await db.execute('CREATE TABLE "order" (id INTEGER PRIMARY KEY, total REAL)');

  await db.insert('notes', {'id': 1, 'title': 'First', 'pinned': 0});
  await db.insert('notes', {'id': 2, 'title': 'Second', 'pinned': 1});
  await db.insert('tags', {'name': 'flutter', 'color': 'blue'});
  await db.insert('plain', {'a': 'x', 'b': 'y'});
  await db.insert('order', {'id': 1, 'total': 9.99});
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(_open);
  tearDown(() => db.close());

  group('discovery', () {
    test('one adapter per table, internals excluded', () async {
      final adapters = await SqfliteStorage.tables(db);

      expect(adapters.map((a) => a.name), containsAll(['notes (SQLite)', 'tags (SQLite)', 'plain (SQLite)', 'order (SQLite)']));
      expect(adapters.any((a) => a.name.startsWith('sqlite_')), isFalse);
    });

    test('writable: false is honoured, so a database can be browsed safely', () async {
      final adapters = await SqfliteStorage.tables(db, writable: false);
      expect(adapters.every((a) => !a.writable), isTrue);
    });
  });

  group('reading', () {
    test('rows are keyed by primary key, which is stripped from the value', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      final all = await notes.readAll();

      expect(all.keys, containsAll(['1', '2']));
      final row = all['1']! as Map;
      expect(row['title'], 'First');
      expect(row.containsKey('id'), isFalse, reason: 'the id IS the key');
    });

    test('a TEXT primary key works, not just INTEGER', () async {
      final tags = await SqfliteStorage.table(db, 'tags');
      final all = await tags.readAll();

      expect(all.keys, ['flutter']);
      expect((all['flutter']! as Map)['color'], 'blue');
    });

    test('a table with NO primary key falls back to rowid rather than being skipped', () async {
      final plain = await SqfliteStorage.table(db, 'plain');
      final all = await plain.readAll();

      expect(all.keys, ['1'], reason: 'rowid');
      expect((all['1']! as Map)['a'], 'x');
    });

    test('a table named after a SQL keyword is readable', () async {
      // Unquoted, `SELECT * FROM order` is a syntax error.
      final order = await SqfliteStorage.table(db, 'order');
      expect((await order.readAll()).keys, ['1']);
    });
  });

  group('writing', () {
    test('updates a row', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      await notes.write('1', {'title': 'Edited', 'pinned': 1});

      final row = (await notes.readAll())['1']! as Map;
      expect(row['title'], 'Edited');
      expect(row['pinned'], 1);
    });

    test('the key wins over an id in the map, so editing it cannot orphan a row', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      await notes.write('1', {'title': 'x', 'pinned': 0, 'id': 999});

      final all = await notes.readAll();
      expect(all.containsKey('1'), isTrue);
      expect(all.containsKey('999'), isFalse);
    });

    test('a bool becomes 0/1 — SQLite has no bool, but people type one', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      await notes.write('1', {'title': 'x', 'pinned': true});
      expect(((await notes.readAll())['1']! as Map)['pinned'], 1);
    });

    test('a column that does not exist is refused by name', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      await expectLater(
        notes.write('1', {'title': 'x', 'nope': 1}),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('nope'))),
      );
    });

    test('NOT NULL with no default must be provided', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      await expectLater(
        notes.write('1', {'pinned': 1}), // title is NOT NULL
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('title'))),
      );
    });

    test('a NOT NULL column cannot be set to null', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      await expectLater(notes.write('1', {'title': null, 'pinned': 0}), throwsA(isA<FormatException>()));
    });

    test('a column WITH a default may be omitted — SQLite fills it in', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      await notes.write('1', {'title': 'only the title'}); // pinned has a default
      expect(((await notes.readAll())['1']! as Map)['title'], 'only the title');
    });

    test('a wrong-typed value is refused before it reaches SQLite', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      await expectLater(
        notes.write('1', {'title': 42, 'pinned': 0}), // title is TEXT
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('TEXT'))),
      );
    });

    test('a rejected write leaves the row untouched', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      final before = (await notes.readAll())['1'];

      await expectLater(notes.write('1', {'title': 42}), throwsA(isA<FormatException>()));

      expect((await notes.readAll())['1'], before);
    });

    test('writing a key that matches no row says so, rather than silently doing nothing', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      await expectLater(
        notes.write('404', {'title': 'ghost'}),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('404'))),
      );
    });

    test('a non-object value is refused', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      await expectLater(notes.write('1', 'not a map'), throwsA(isA<FormatException>()));
    });
  });

  group('deleting', () {
    test('removes the row', () async {
      final notes = await SqfliteStorage.table(db, 'notes');
      await notes.delete('1');

      final all = await notes.readAll();
      expect(all.containsKey('1'), isFalse);
      expect(all.containsKey('2'), isTrue, reason: 'only the one row');
    });

    test('works for a TEXT key too', () async {
      final tags = await SqfliteStorage.table(db, 'tags');
      await tags.delete('flutter');
      expect(await tags.readAll(), isEmpty);
    });
  });
}
