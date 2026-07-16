// Proves the SQLite adapter actually round-trips through DebugStorageAdapter —
// a relational store is the interface's hardest case, so it's worth checking
// against a real database rather than assuming.
import 'package:devtray_example/notes_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async => NotesDb.init());

  final adapter = NotesDbAdapter();

  test('readAll keys rows by primary key, and strips id from the value', () async {
    final all = await adapter.readAll();

    expect(all.keys, contains('1'));
    final row = all['1']! as Map;
    expect(row['title'], 'Note 1');
    expect(row.containsKey('id'), isFalse, reason: 'the id IS the key — showing it twice invites orphaning the row');
  });

  test('write updates the row', () async {
    await adapter.write('1', {'title': 'Edited', 'body': 'new body', 'pinned': 1});

    final row = (await adapter.readAll())['1']! as Map;
    expect(row['title'], 'Edited');
    expect(row['pinned'], 1);
  });

  test('write puts the id back from the key, so editing it cannot orphan a row', () async {
    // The editor can't show `id`, but someone could still add it back by hand.
    await adapter.write('1', {'title': 'x', 'body': 'y', 'pinned': 0, 'id': 999});

    final all = await adapter.readAll();
    expect(all.containsKey('1'), isTrue);
    expect(all.containsKey('999'), isFalse);
  });

  test('a bool for pinned is accepted — SQLite has no bool, but people type one', () async {
    await adapter.write('2', {'title': 'x', 'body': 'y', 'pinned': true});
    expect(((await adapter.readAll())['2']! as Map)['pinned'], 1);
  });

  test('a missing column is refused, and nothing is written', () async {
    final before = (await adapter.readAll())['1'];

    expect(
      () => adapter.write('1', {'title': 'only a title'}),
      throwsA(isA<FormatException>()),
    );

    expect((await adapter.readAll())['1'], before);
  });

  test('a wrong-typed column is refused', () {
    expect(
      () => adapter.write('1', {'title': 42, 'body': 'y', 'pinned': 0}),
      throwsA(isA<FormatException>()),
    );
  });

  test('a non-object value is refused', () {
    expect(() => adapter.write('1', 'not a map'), throwsA(isA<FormatException>()));
  });

  test('delete removes the row', () async {
    await adapter.delete('1');
    expect((await adapter.readAll()).containsKey('1'), isFalse);
  });
}
