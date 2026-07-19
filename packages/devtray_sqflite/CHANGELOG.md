# Changelog

## 0.2.0

- Table reads are capped at `maxRows` (default 500) rather than an unbounded `SELECT *`.
  A real table — a sync log, a cache, an events table — pulled every row into memory on
  the UI isolate and built a `Map` per row, enough to freeze the panel for seconds.
- The cap is surfaced through the new `DebugStorageAdapter.notice`, so a partial view
  says so instead of reading as the whole table.

## 0.1.0

* Initial release — split out of the `devtray` core so apps compile only the
  integrations they use.
