import 'package:debug_overlay/debug_overlay.dart';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

/// A user fetched from jsonplaceholder and cached in Hive.
///
/// Hand-written adapter rather than a generated one — this is an example, and a
/// build_runner step would only get in the way.
class User {
  final int id;
  final String name;
  final String username;
  final String email;
  final String city;

  const User({required this.id, required this.name, required this.username, required this.email, required this.city});

  /// From the API's shape — `city` is nested under `address`.
  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    name: json['name'] as String,
    username: json['username'] as String,
    email: json['email'] as String,
    city: (json['address'] as Map<String, dynamic>)['city'] as String,
  );

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'username': username, 'email': email, 'city': city};

  /// The mirror of [toMap] — rebuilds a user from the flat map the Storage page
  /// edits. Not [fromJson]: that takes the API's *nested* shape, which isn't
  /// what's in the box.
  ///
  /// [id] comes from the caller (the box key) rather than the map, so renaming
  /// `"id"` in the editor can't orphan the record. Every field is required and
  /// cast here, so a bad edit fails with a clear error instead of putting a
  /// half-built User in the box.
  factory User.fromMap(int id, Map<String, Object?> map) => User(
    id: id,
    name: map['name']! as String,
    username: map['username']! as String,
    email: map['email']! as String,
    city: map['city']! as String,
  );

  User copyWith({String? name, String? username, String? email, String? city}) =>
      User(id: id, name: name ?? this.name, username: username ?? this.username, email: email ?? this.email, city: city ?? this.city);

  @override
  String toString() => '$name (@$username) · $email · $city';
}

class UserAdapter extends TypeAdapter<User> {
  @override
  final int typeId = 1;

  @override
  User read(BinaryReader reader) =>
      User(id: reader.readInt(), name: reader.readString(), username: reader.readString(), email: reader.readString(), city: reader.readString());

  @override
  void write(BinaryWriter writer, User user) {
    writer
      ..writeInt(user.id)
      ..writeString(user.name)
      ..writeString(user.username)
      ..writeString(user.email)
      ..writeString(user.city);
  }
}

const usersBoxName = 'users';

Box<User> get usersBox => Hive.box<User>(usersBoxName);

/// Fetches the jsonplaceholder users and caches them, keyed by id.
///
/// Goes through the same `dio` the overlay is watching, so the request shows up
/// on the Network page too.
///
/// `/users` is a fixed **10-item** resource — no `?_limit=` or paging will get
/// you more, because jsonplaceholder simply doesn't have more. (`/photos` has
/// 5000 and `/comments` 500, but they aren't users.) So to fill the box with
/// enough rows to actually exercise scrolling, the 10 real users are fanned out
/// to [count] by cloning them with fresh ids.
///
/// Still exactly one real request — the demo stays honest.
Future<int> fetchAndStoreUsers(Dio dio, {int count = 100}) async {
  final res = await dio.get<List<dynamic>>('https://jsonplaceholder.typicode.com/users');

  final real = (res.data ?? []).map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
  final users = fanOut(real, count);

  await usersBox.putAll({for (final u in users) u.id.toString(): u});
  return usersBox.length;
}

/// Clones [real] up to [count] users, giving each clone a fresh id.
///
/// The first pass through is returned untouched, so the genuine records are
/// visible as-is; only the padding is synthesised.
List<User> fanOut(List<User> real, int count) {
  if (real.isEmpty) return const [];

  return [
    for (var i = 0; i < count; i++)
      if (i < real.length)
        real[i]
      else
        () {
          final source = real[i % real.length];
          final round = i ~/ real.length;
          return User(
            id: i + 1,
            name: '${source.name} #${round + 1}',
            username: '${source.username}$round',
            email: source.email.replaceFirst('@', '+$round@'),
            city: source.city,
          );
        }(),
  ];
}

/// Exposes the typed Hive box to the Storage page.
///
/// This is the whole point of `DebugStorageAdapter` being an interface rather
/// than a bundled Hive adapter: the box holds `User` objects, not primitives, so
/// a generic adapter could only ever print them. Only the app knows what a value
/// *means*. An encrypted box would work identically — you just hand over an
/// already-open, already-decrypted handle.
///
/// Values are surfaced as **maps** (`User.toMap()`), so the Storage page shows
/// and edits the user as JSON — the object's real shape, with every field named.
/// That's what makes it safely editable through a generic key/value page: you're
/// changing `"city": "London"`, not re-typing a summary line and hoping a regex
/// parses it back.
///
/// The custom Users page still gives each field its own input, which is nicer.
/// This is the same data, browsable next to your other stores.
class UsersBoxAdapter extends DebugStorageAdapter {
  @override
  String get name => 'Users (Hive)';

  @override
  Future<Map<String, Object?>> readAll() async {
    return {for (final key in usersBox.keys) key.toString(): usersBox.get(key)?.toMap()};
  }

  @override
  Future<void> write(String key, Object? value) async {
    if (value is! Map) {
      throw FormatException('Expected a JSON object, got ${value.runtimeType}');
    }

    // Rebuild through the model rather than trusting the map — a missing or
    // wrong-typed field fails here, not later when something reads the box. The
    // id comes from the key, so renaming it in the editor can't orphan the
    // record.
    final map = value.map((k, v) => MapEntry(k.toString(), v));
    await usersBox.put(key, User.fromMap(int.parse(key), map));
  }

  @override
  Future<void> delete(String key) async => usersBox.delete(key);
}
