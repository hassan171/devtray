# Changelog

## 0.4.0

No changes of its own, but the core renamed several public types — see its
changelog for the migration table. Requires `devtray ^0.4.0`.

## 0.3.0

No changes. Versioned in step with the rest of the set, and requires
`devtray ^0.3.0` — see the core's changelog for the new Timeline page.

## 0.2.0

First release. Versioned in step with the rest of the set rather than starting at 0.1.0,
so every package in the family carries the same number.

- `FileLogSink` writes captured logs to rotating files on disk. One file per app run,
  rolled over past `maxBytes`, pruned past `maxFiles` — which counts **sessions, not
  files**, and evicts them whole so a multi-part run can't be left starting mid-story.
- `LogSessionLoader` reads them back, and `DevtrayFileSessions` adapts it to
  `LogsDebugPage(sessionSource: ...)` for the in-app session browser.
- JSON Lines by default, so a crash mid-write costs the last line rather than the file.
  Pass `format: formatLogEntryAsText` for a human-readable log (not loadable back).
- `LogFileLocation` picks cache (default), documents or temporary — on iOS that decides
  whether the log is backed up and user-visible.
