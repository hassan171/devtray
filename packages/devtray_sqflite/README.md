# devtray_sqflite

Browse and edit SQLite tables from devtray's **Storage** page.

Part of [devtray](https://github.com/hassan171/devtray) — the overlay, the pages and the stores live in the
core package; this is just the sqflite glue.

## Install

```yaml
dependencies:
  devtray: ^0.6.2
  devtray_sqflite: ^0.6.2
```

## Usage

Hand it a `Database` and every table shows up — discovered from the schema, so
there's nothing to list by hand:

```dart
import 'package:devtray_sqflite/devtray_sqflite.dart';

StorageDebugPage(adapters: [
  ...await SqfliteStorage.tables(db),
]);
```

`tables()` returns **one adapter per table** — each becomes a store you drill
into, keyed by its own primary key. Pass `writable: false` for a database you
only want to read.

## What it can and can't know

Everything comes from SQLite's own introspection — `sqlite_master` for the table
list, `PRAGMA table_info` for columns, types, NOT NULL flags and primary keys.
That's enough to validate the *shape* of an edit before it reaches the database,
so a typo is a readable message instead of a raw SQL error.

What it **cannot** know is what your data *means*: that `pinned` is 0/1, that
`status` is one of four strings, that `email` should contain an `@`. If those
rules matter, write an adapter by hand.

## Docs

Full setup and the other integrations: **[https://github.com/hassan171/devtray](https://github.com/hassan171/devtray)**

## License

MIT — see [LICENSE](LICENSE).
