# Changelog

## 0.6.2

No changes of its own. The core added header redaction to `..network(...)` — hidden headers
are masked or omitted from the pane, cURL, exports and the bug report. See its changelog.

## 0.6.1

No changes of its own. The core added `..capture(bool)` to `configure` — see its changelog.

## 0.6.0

### Added

- **`FileNetworkSink`** — captured requests land on disk, a file per run, the network
  counterpart to `FileLogSink`. Written when a request *completes*, since the status, body and
  duration all arrive with the response; anything still in flight is flushed when the app is
  backgrounded, so a process killed mid-request still leaves a record.

  ```dart
  ..networkToAsync(FileNetworkSink.open)
  ```

- **`NetworkSessionLoader`** — reads those files back, so the Network page's session picker
  can offer past runs the way the Logs page already did. Give it the **same** `location` as
  the sink, or it looks in the wrong place and finds nothing.

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
