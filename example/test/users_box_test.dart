import 'dart:io';

import 'package:debug_overlay_example/users_box.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Exercises the Hive round-trip the example demonstrates: a TYPED box, read
/// through a hand-written DebugStorageAdapter.
///
/// This is the case that justified shipping `DebugStorageAdapter` as an interface
/// rather than a bundled Hive adapter — the box holds `User` objects, not
/// primitives, so only the app can say what a value *means*.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('debug_overlay_hive_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UserAdapter());
    await Hive.openBox<User>(usersBoxName);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  const ada = User(
    id: 1,
    name: 'Ada Lovelace',
    username: 'ada',
    email: 'ada@example.com',
    city: 'London',
  );

  group('the typed box', () {
    test('a User survives a write/read round-trip', () async {
      await usersBox.put('1', ada);

      // Closing and reopening forces it through the TypeAdapter, not just memory.
      await usersBox.close();
      await Hive.openBox<User>(usersBoxName);

      final read = usersBox.get('1')!;
      expect(read.id, 1);
      expect(read.name, 'Ada Lovelace');
      expect(read.username, 'ada');
      expect(read.email, 'ada@example.com');
      expect(read.city, 'London');
    });
  });

  group('fanOut — /users only has 10 real records', () {
    // No `?_limit=` or paging gets you more; jsonplaceholder simply doesn't have
    // them. So the 10 are cloned up to the requested count, to make a box big
    // enough to actually exercise scrolling.

    const alan = User(id: 2, name: 'Alan Turing', username: 'alan', email: 'alan@example.com', city: 'Wilmslow');

    test('returns the real records untouched, then synthesises the rest', () {
      final users = fanOut([ada, alan], 5);

      expect(users, hasLength(5));

      // The genuine data is visible as-is.
      expect(users[0], same(ada));
      expect(users[1], same(alan));

      // The padding is clearly marked as such.
      expect(users[2].name, 'Ada Lovelace #2');
      expect(users[2].email, 'ada+1@example.com');
      expect(users[3].name, 'Alan Turing #2');
      expect(users[4].name, 'Ada Lovelace #3');
    });

    test('every id is unique, so nothing overwrites anything in the box', () {
      final users = fanOut([ada, alan], 100);

      expect(users, hasLength(100));
      expect(users.map((u) => u.id).toSet(), hasLength(100));
    });

    test('asking for fewer than there are just truncates', () {
      expect(fanOut([ada, alan], 1), [ada]);
    });

    test('an empty fetch yields nothing, rather than dividing by zero', () {
      expect(fanOut([], 100), isEmpty);
    });

    test('1000 users is fine', () {
      final users = fanOut([ada, alan], 1000);
      expect(users, hasLength(1000));
      expect(users.map((u) => u.id).toSet(), hasLength(1000));
    });
  });

  group('UsersBoxAdapter', () {
    late UsersBoxAdapter adapter;

    setUp(() {
      adapter = UsersBoxAdapter();
    });

    test('readAll surfaces each user as a map — the object\'s real shape', () async {
      await usersBox.put('1', ada);

      final all = await adapter.readAll();

      expect(all.keys, ['1']);
      // A map, not a summary string: every field named, so the Storage page can
      // render and edit it as JSON.
      expect(all['1'], {
        'id': 1,
        'name': 'Ada Lovelace',
        'username': 'ada',
        'email': 'ada@example.com',
        'city': 'London',
      });
    });

    test('write rebuilds the typed model from the edited map', () async {
      await usersBox.put('1', ada);

      await adapter.write('1', {
        'id': 1,
        'name': 'Grace Hopper',
        'username': 'grace',
        'email': 'grace@navy.mil',
        'city': 'New York',
      });

      // Reopen so it goes through the TypeAdapter, not just memory.
      await usersBox.close();
      await Hive.openBox<User>(usersBoxName);

      final updated = usersBox.get('1')!;
      expect(updated.name, 'Grace Hopper');
      expect(updated.username, 'grace');
      expect(updated.email, 'grace@navy.mil');
      expect(updated.city, 'New York');
    });

    test('the id comes from the KEY, so editing it in the map cannot orphan the record', () async {
      await usersBox.put('1', ada);

      await adapter.write('1', {
        'id': 999, // ← ignored
        'name': 'Ada Lovelace',
        'username': 'ada',
        'email': 'ada@example.com',
        'city': 'London',
      });

      expect(usersBox.get('1')!.id, 1);
      expect(usersBox.get('999'), isNull);
    });

    test('a missing field is rejected, not silently written', () async {
      await usersBox.put('1', ada);

      // Rebuilding through the model means a bad map fails HERE, not later when
      // something reads the box.
      expect(
        () => adapter.write('1', {'name': 'Ada'}),
        throwsA(isA<TypeError>()),
      );
      expect(usersBox.get('1')!.name, 'Ada Lovelace');
    });

    test('a non-map value is rejected', () async {
      expect(
        () => adapter.write('1', 'just a string'),
        throwsA(isA<FormatException>()),
      );
    });

    test('delete removes the user', () async {
      await usersBox.put('1', ada);

      await adapter.delete('1');

      expect(usersBox.get('1'), isNull);
      expect(await adapter.readAll(), isEmpty);
    });
  });

  group('editing a user (what the Users page does)', () {
    test('copyWith updates the fields and keeps the id', () async {
      await usersBox.put('1', ada);

      // Exactly what UserTile._save does.
      await usersBox.put(
        '1',
        ada.copyWith(
          name: 'Grace Hopper',
          username: 'grace',
          email: 'grace@navy.mil',
          city: 'New York',
        ),
      );

      // Reopen so it goes through the TypeAdapter, not just memory.
      await usersBox.close();
      await Hive.openBox<User>(usersBoxName);

      final updated = usersBox.get('1')!;
      expect(updated.name, 'Grace Hopper');
      expect(updated.username, 'grace');
      expect(updated.email, 'grace@navy.mil');
      expect(updated.city, 'New York');
      // The id is the key — it isn't editable.
      expect(updated.id, 1);
    });
  });
}
