# devtray_hive

Browse and edit Hive boxes from devtray's **Storage** page.

Part of [devtray](https://github.com/hassan171/devtray) — the overlay, the pages and the stores live in the
core package; this is just the Hive glue.

## Install

```yaml
dependencies:
  devtray: ^0.1.0
  devtray_hive: ^0.1.0
```

## Usage

Register a box by opening it through `HiveStorage` — it returns the same box
`Hive` does, so it's a drop-in:

```dart
import 'package:devtray_hive/devtray_hive.dart';

// was: await Hive.openBox<String>('settings');
await HiveStorage.openBox<String>('settings');

StorageDebugPage(adapters: HiveStorage.boxes)
```

## Typed boxes

A box of primitives needs nothing more. A box of *your* objects needs one thing
Hive can't supply — how to turn the object into named fields, and back:

```dart
await HiveStorage.openBox<User>(
  'users',
  toMap: (u) => u.toMap(),
  fromMap: (key, map) => User.fromMap(map),   // omit for read-only
);
```

Without `toMap` a typed box is registered **read-only** and its values are shown
as `toString()` — browsable, and honest about being un-editable.

## Why registration, when SQLite needs none

Hive can't be introspected: there's no way to list open boxes, no schema, and no
reflection to turn a `User` into named fields. So rather than asking Hive what
exists, your app declares it at the one moment it already knows both the name and
the type — the `openBox` call.

## Docs

Full setup and the other integrations: **[https://github.com/hassan171/devtray](https://github.com/hassan171/devtray)**

## License

MIT — see [LICENSE](LICENSE).
