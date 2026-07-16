import 'package:hive_ce/hive.dart';

/// A typed model for the tests — the case that actually exercises the wrapper.
///
/// A box of primitives proves very little: its values are already maps, so a
/// generic reader handles them. The interesting question is a `Box<User>`, where
/// Dart has no reflection to turn a value into named fields — that's what
/// `toMap`/`fromMap` exist for, and what makes a box read-only without them.
///
/// Hand-written adapter rather than a generated one: a build_runner step in a
/// test fixture would only get in the way.
class User {
  final int id;
  final String name;
  final String username;
  final String email;
  final String city;

  const User({required this.id, required this.name, required this.username, required this.email, required this.city});

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'username': username, 'email': email, 'city': city};

  /// [id] comes from the caller (the box key) rather than the map, so renaming
  /// `"id"` in the editor can't orphan the record.
  factory User.fromMap(int id, Map<String, Object?> map) => User(
        id: id,
        name: map['name']! as String,
        username: map['username']! as String,
        email: map['email']! as String,
        city: map['city']! as String,
      );

  @override
  String toString() => '$name (@$username) · $email · $city';
}

class UserAdapter extends TypeAdapter<User> {
  @override
  final int typeId = 1;

  @override
  User read(BinaryReader reader) => User(
        id: reader.readInt(),
        name: reader.readString(),
        username: reader.readString(),
        email: reader.readString(),
        city: reader.readString(),
      );

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
