# Changelog

## 0.5.0

No changes of its own. The core folded `DevtrayKillSwitch` and `DevtrayController` into
`Devtray` and reshaped `runDebugApp`'s signature — see its changelog for the migration table.

## 0.4.0

No changes of its own, but the core renamed several public types — see its
changelog for the migration table. Requires `devtray ^0.4.0`.

## 0.3.0

No changes. Versioned in step with the rest of the set, and requires
`devtray ^0.3.0` — see the core's changelog for the new Timeline page.

## 0.2.0

- Table reads are capped at `maxRows` (default 500) rather than an unbounded `SELECT *`.
  A real table — a sync log, a cache, an events table — pulled every row into memory on
  the UI isolate and built a `Map` per row, enough to freeze the panel for seconds.
- The cap is surfaced through the new `DebugStorageAdapter.notice`, so a partial view
  says so instead of reading as the whole table.

## 0.1.0

* Initial release — split out of the `devtray` core so apps compile only the
  integrations they use.
