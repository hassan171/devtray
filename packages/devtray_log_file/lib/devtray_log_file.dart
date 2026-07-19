/// File persistence for `devtray`'s captured logs — write them to disk, and
/// read a past run back.
///
/// [LogStore] is a ring buffer that dies with the process, which means the log
/// of the crash you just saw is gone. This is the fix:
///
/// ```dart
/// LogExporter.instance.addSink(await FileLogSink.open());
/// ```
///
/// One file per app run, rotated by size, pruned past a file count. Then, to
/// read one back:
///
/// ```dart
/// final loader = await LogSessionLoader.open();
/// LogsDebugPage(sessionLoader: DevtrayFileSessions(loader));
/// ```
///
/// which puts a session picker on the Logs page — pick a past run and browse it
/// read-only, with the same rows and the same search.
///
/// ## Why this isn't in the core
///
/// The core carries no runtime dependencies and runs everywhere Flutter does.
/// Writing a file needs `dart:io` (absent on web) and a directory to write to,
/// which is a decision only the app can make — a log the user is meant to find
/// and email belongs somewhere very different from scratch diagnostics. So the
/// core defines [LogSink] and owns the batching, and this package owns the one
/// dependency and the platform detail.
///
/// The same interface takes an upload: implement [LogSink.write] with your own
/// HTTP call and the batching, failure handling and flush policy all still
/// apply. The package deliberately doesn't ship an uploader — endpoint, auth,
/// retry and what's allowed to leave the device are the app's to decide.
library;

export 'src/file_log_sink.dart';
export 'src/log_session_loader.dart';
export 'src/devtray_file_sessions.dart';
