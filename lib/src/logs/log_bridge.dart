/// Bridges an existing logging setup into the overlay's Logs page.
///
/// The Logs page reads from [LogStore] and nothing else, so hooking up any
/// logger means: call [LogStore.log] from wherever your logger emits. This file
/// just makes the common shapes convenient — none of it is required.
///
/// ## package:logger
///
/// `logger` writes through `LogOutput`s. Add ours alongside the console one and
/// you keep your existing output untouched:
///
/// ```dart
/// final logger = Logger(
///   output: MultiOutput([ConsoleOutput(), DebugOverlayLogOutput()]),
/// );
/// ```
///
/// [DebugOverlayLogOutput] is not defined here (it would drag `logger` into the
/// package's dependencies for everyone). Copy this — it's the whole thing:
///
/// ```dart
/// class DebugOverlayLogOutput extends LogOutput {
///   @override
///   void output(OutputEvent event) {
///     LogStore.instance.log(
///       event.lines.join('\n'),
///       level: debugLevelFromName(event.level.name),
///     );
///   }
/// }
/// ```
///
/// ## talker
///
/// ```dart
/// talker.stream.listen((data) {
///   LogStore.instance.log(
///     data.message ?? '',
///     level: debugLevelFromName(data.logLevel?.name),
///     tag: data.title,
///     error: data.exception ?? data.error,
///     stackTrace: data.stackTrace,
///   );
/// });
/// ```
///
/// ## dart:developer / your own logger
///
/// ```dart
/// void myLog(String msg, {String? tag}) {
///   LogStore.instance.log(msg, tag: tag, level: LogLevel.info);
///   dev.log(msg, name: tag ?? '');
/// }
/// ```
///
/// ## package:logging
///
/// ```dart
/// Logger.root.onRecord.listen((r) {
///   LogStore.instance.log(
///     r.message,
///     tag: r.loggerName,
///     level: debugLevelFromName(r.level.name),
///     error: r.error,
///     stackTrace: r.stackTrace,
///   );
/// });
/// ```
library;

import 'log_store.dart';

/// Maps a foreign level name onto a [LogLevel].
///
/// Handles the names used by `logger`, `logging`, `talker` and most homegrown
/// loggers — case-insensitive, and tolerant of the aliases each package picks
/// (`severe`/`fatal`/`wtf` all mean error; `fine`/`finer`/`trace`/`verbose` all
/// mean debug). Anything unrecognised falls back to [fallback].
LogLevel debugLevelFromName(String? name, {LogLevel fallback = LogLevel.debug}) {
  return switch (name?.toLowerCase().trim()) {
    'error' || 'severe' || 'fatal' || 'shout' || 'wtf' || 'critical' => LogLevel.error,
    'warning' || 'warn' => LogLevel.warning,
    'info' || 'information' || 'config' || 'good' => LogLevel.info,
    'debug' || 'fine' || 'finer' || 'finest' || 'trace' || 'verbose' => LogLevel.debug,
    _ => fallback,
  };
}

/// Maps a numeric severity onto a [LogLevel], for loggers that expose an int.
///
/// Uses the `package:logging` scale (FINE 500 / INFO 800 / WARNING 900 /
/// SEVERE 1000), which `dart:developer`'s `log(level:)` also follows.
LogLevel debugLevelFromSeverity(int severity) {
  if (severity >= 1000) return LogLevel.error;
  if (severity >= 900) return LogLevel.warning;
  if (severity >= 800) return LogLevel.info;
  return LogLevel.debug;
}
