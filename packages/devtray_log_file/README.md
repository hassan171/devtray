# devtray_log_file

Write [devtray](../devtray)'s captured logs to disk, and load a past run back into the Logs page.

`LogStore` is an in-memory ring buffer: 1000 entries, oldest dropped, gone when the process
exits. That's the right default for a debug overlay, but it means the log of the crash you
just saw died with the app. This is the fix.

## Setup

```dart
import 'package:devtray_log_file/devtray_log_file.dart';

LogExporter.instance.addSink(await FileLogSink.open());
```

That's the whole opt-in. Every captured line is now written as well as buffered — including
lines the ring buffer later evicts, so a long session lands on disk in full even though the
page only ever shows the last 1000.

To read past runs back, hand the Logs page a session source:

```dart
final loader = await LogSessionLoader.open();

LogsDebugPage(sessionSource: DevtrayFileSessions(loader))
```

A folder button appears beside the search field. Pick a run and it opens read-only, clearly
marked as not live, with the same rows and the same search.

## Where the files go

| `LogFileLocation` | Directory | Backed up | OS may delete |
|---|---|---|---|
| `cache` (default) | `getApplicationCacheDirectory()` | No | Yes |
| `documents` | `getApplicationDocumentsDirectory()` | Yes | No |
| `temporary` | `getTemporaryDirectory()` | No | Yes, aggressively |

`cache` is the default because logs are diagnostic scratch data. Use `documents` when the
log is something the **user** is meant to find and send on — on iOS that also makes it
visible in the Files app if the app opts in.

Whichever you pick, `LogSessionLoader.open()` must be given the *same* location as the sink,
or it will look in the wrong place and find nothing.

## Rotation

One file per app run. A file that grows past `maxBytes` rolls over to a new one; files past
`maxFiles` are deleted oldest-first.

```dart
await FileLogSink.open(
  maxBytes: 5 * 1024 * 1024,   // default
  maxFiles: 5,                 // default
);
```

One file per run rather than one rolling file, because the question a log answers is almost
always *"what happened in the run that broke"* — and a single rolling file makes you find
those boundaries yourself. The cost is that a crash-restart loop makes files quickly, which
is what `maxFiles` bounds.

## Format

JSON Lines (`formatLogEntryAsJson`) by default — one JSON object per line. A crash mid-write
costs the last line rather than making the whole file unparseable, and `parseLogEntries`
skips damaged lines for the same reason: the files worth reading are often the ones the app
died halfway through writing.

For a file meant only for human eyes, pass `format: formatLogEntryAsText`. Note that the
session loader can't parse it back.

## Sending logs somewhere else

There's no separate uploader, because there doesn't need to be — a remote destination is
just another `LogSink`:

```dart
class UploadSink extends LogSink {
  @override
  String get name => 'Upload';

  @override
  Future<void> write(List<LogEntry> batch) async {
    await dio.post('/logs', data: {'lines': batch.map(formatLogEntryAsJson).toList()});
  }
}

LogExporter.instance.addSink(UploadSink());
```

The batching, flush policy and failure handling all apply unchanged, and sinks fan out — a
file for later and an upload for now, both fed from one buffer.

Nothing is bundled for this on purpose. The endpoint, the auth, the retry policy and the
judgement about what may leave the device are the app's decisions, and a package that made
them for you would be wrong for most apps.

## When logs get written

Set the policy on `LogExporter`:

```dart
LogExporter.instance.policy = const FlushPolicy.batched(size: 50, interval: Duration(seconds: 5));
```

| Policy | Loses on crash | Cost |
|---|---|---|
| `immediate()` | Nothing | I/O per log line, on the calling thread |
| `batched()` (default) | Up to one interval | One write per batch |
| `manual()` | Everything since the last `flush()` | Nothing until you ask |

`LogExporter.flushOnPause` (on by default) flushes when the app is backgrounded — the last
moment before the OS may kill the process, and what makes `batched` safe enough to be the
default. It needs `LogExporter.observeLifecycle()`, which `runDebugApp` calls for you.

## Failure handling

A sink that throws is disabled for the rest of the session and the failure is reported into
the log itself, where you'll see it on the Logs page — rather than being allowed to take
down the app it's meant to be diagnosing. One bad sink doesn't stop the others.

`LogExporter.failedSinks` lists what broke; `retrySink(name)` re-enables one.

## Why this isn't in devtray itself

The core carries no runtime dependencies and runs everywhere Flutter does. Writing a file
needs `dart:io` (absent on web) and `path_provider` (no web implementation), plus a choice
of directory that only the app can make. So the core defines `LogSink` and owns the
batching; this package owns the dependency and the platform detail.
