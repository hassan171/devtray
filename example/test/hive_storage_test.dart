// Hive can't be discovered, so the wrapper's job is to capture what only the app
// knows — the box's name and type — at the moment it opens it. These check that
// the capture is right, and that a box it CAN'T edit is honest about it.
import 'dart:io';

import 'package:debug_overlay_example/hive_storage.dart';
import 'package:debug_overlay_example/users_box.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

late Directory dir;

void main() {
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_storage_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UserAdapter());
    HiveStorage.reset();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('a box of primitives needs no converter', () {
    test('opens, registers, and reads through', () async {
      final box = await HiveStorage.openBox<String>('settings');
      await box.putAll({'theme': 'dark', 'locale': 'en'});

      expect(HiveStorage.boxes, hasLength(1));
      final adapter = HiveStorage.boxes.single;
      expect(adapter.name, 'settings (Hive)');
      expect(await adapter.readAll(), {'theme': 'dark', 'locale': 'en'});
    });

    test('returns the same box Hive would — it stays a drop-in', () async {
      final box = await HiveStorage.openBox<String>('settings');
      expect(box, same(Hive.box<String>('settings')));
      expect(box.name, 'settings');
    });

    test('writes and deletes reach the box', () async {
      final box = await HiveStorage.openBox<String>('settings');
      await box.put('theme', 'dark');

      final adapter = HiveStorage.boxes.single;
      await adapter.write('theme', 'light');
      expect(box.get('theme'), 'light');

      await adapter.delete('theme');
      expect(box.containsKey('theme'), isFalse);
    });

    test('a value of the wrong type is refused, naming the box type', () async {
      await HiveStorage.openBox<String>('settings');
      await expectLater(
        HiveStorage.boxes.single.write('theme', 42),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('String'))),
      );
    });
  });

  group('a typed box', () {
    const alice = User(id: 1, name: 'Alice', username: 'alice', email: 'a@e.com', city: 'London');

    test('with toMap/fromMap shows named fields and edits as JSON', () async {
      final box = await HiveStorage.openBox<User>(
        'users',
        toMap: (u) => u.toMap(),
        fromMap: (key, map) => User.fromMap(int.parse(key), map),
      );
      await box.put('1', alice);

      final adapter = HiveStorage.boxes.single;
      expect(adapter.writable, isTrue);

      // Named fields, not "Instance of 'User'".
      final row = (await adapter.readAll())['1']! as Map;
      expect(row['name'], 'Alice');
      expect(row['city'], 'London');

      await adapter.write('1', {...alice.toMap(), 'city': 'Berlin'});
      expect(box.get('1')!.city, 'Berlin');
    });

    test('the key wins over an id in the map, so editing it cannot orphan a record', () async {
      final box = await HiveStorage.openBox<User>(
        'users',
        toMap: (u) => u.toMap(),
        fromMap: (key, map) => User(
          id: int.parse(key), // from the key, not the map
          name: map['name']! as String,
          username: map['username']! as String,
          email: map['email']! as String,
          city: map['city']! as String,
        ),
      );
      await box.put('1', alice);

      await HiveStorage.boxes.single.write('1', {...alice.toMap(), 'id': 999});
      expect(box.get('1')!.id, 1);
    });

    test('WITHOUT toMap it is read-only — an edit control that cannot write would be a lie', () async {
      final box = await HiveStorage.openBox<User>('users');
      await box.put('1', alice);

      final adapter = HiveStorage.boxes.single;
      expect(adapter.writable, isFalse);
      // toString() is all Dart offers without reflection. Browsable, not editable.
      expect((await adapter.readAll())['1'], contains('Alice'));
    });

    test('toMap with no fromMap is read-only too — there is no way back', () async {
      await HiveStorage.openBox<User>('users', toMap: (u) => u.toMap());
      expect(HiveStorage.boxes.single.writable, isFalse);
    });

    test('a non-object value is refused when a converter is set', () async {
      await HiveStorage.openBox<User>(
        'users',
        toMap: (u) => u.toMap(),
        fromMap: (key, map) => alice,
      );
      await expectLater(HiveStorage.boxes.single.write('1', 'nope'), throwsA(isA<FormatException>()));
    });
  });

  test('several boxes register in order', () async {
    await HiveStorage.openBox<String>('settings');
    await HiveStorage.openBox<int>('counters');

    expect(HiveStorage.boxes.map((a) => a.name), ['settings (Hive)', 'counters (Hive)']);
  });

  test('register() covers a box opened elsewhere', () async {
    final box = await Hive.openBox<String>('opened_by_someone_else');
    HiveStorage.register<String>(box, label: 'Custom label');

    expect(HiveStorage.boxes.single.name, 'Custom label');
  });

  group('registering the same box twice', () {
    // Hive's openBox RETURNS THE EXISTING INSTANCE if the box is already open —
    // it doesn't throw. So a second call from a retried bootstrap, a hot restart,
    // or two call sites that both want the box succeeds silently, and without a
    // guard would put the same store in the list twice.

    test('openBox twice registers once', () async {
      await HiveStorage.openBox<String>('settings');
      await HiveStorage.openBox<String>('settings');

      expect(HiveStorage.boxes, hasLength(1));
    });

    test('register twice registers once', () async {
      final box = await Hive.openBox<String>('settings');
      HiveStorage.register<String>(box);
      HiveStorage.register<String>(box);

      expect(HiveStorage.boxes, hasLength(1));
    });

    test('the first registration wins — a re-register cannot silently drop a converter', () async {
      await HiveStorage.openBox<String>('settings', label: 'First');
      await HiveStorage.openBox<String>('settings', label: 'Second');

      expect(HiveStorage.boxes.single.name, 'First');
    });

    test('names are matched case-insensitively, like Hive itself', () async {
      // Hive lowercases box names internally, so `Settings` and `settings` are
      // the same box — the guard has to agree, or the same box registers twice.
      final box = await Hive.openBox<String>('settings');
      HiveStorage.register<String>(box);
      expect(HiveStorage.isRegistered('SETTINGS'), isTrue);

      HiveStorage.register<String>(Hive.box<String>('Settings'));
      expect(HiveStorage.boxes, hasLength(1));
    });

    test('different boxes still both register', () async {
      await HiveStorage.openBox<String>('settings');
      await HiveStorage.openBox<int>('counters');

      expect(HiveStorage.boxes, hasLength(2));
    });
  });
}
