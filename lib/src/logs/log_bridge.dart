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
/// ## dart:developer
///
/// **`dart:developer`'s `log()` cannot be captured.** Every other channel the
/// overlay hooks works by grabbing a Dart-level indirection point: `print` has a
/// `ZoneSpecification` entry, `debugPrint` is a reassignable global,
/// `FlutterError.onError` is an assignable handler. `developer.log` is declared
/// `external` in the SDK — implemented natively, straight to the VM service
/// protocol for the DevTools Logging view. There is no hook to install.
///
/// So it has to be bridged at the call site instead. [debugLog] is a drop-in
/// with the same signature — swap the import and every existing `log(...)` call
/// keeps working, but now also lands in the Logs page:
///
/// ```dart
/// // import 'dart:developer';
/// import 'package:debug_overlay/debug_overlay.dart';
///
/// log('user signed in', name: 'auth');   // now visible in DevTools *and* the overlay
/// ```
///
/// If `log` collides with something in scope, import it under a prefix or use
/// [debugLog] directly.
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

import 'dart:async';
import 'dart:developer' as developer;

import 'log_store.dart';

/// A drop-in replacement for `dart:developer`'s `log()` that also records into
/// [LogStore], so the line shows up on the Logs page.
///
/// `developer.log` is `external` — implemented by the VM, with no hook to
/// intercept (see the library docs above). Bridging at the call site is the only
/// option, so this mirrors its signature exactly: swap
/// `import 'dart:developer'` for `package:debug_overlay/debug_overlay.dart` and
/// existing `log(...)` calls keep compiling unchanged.
///
/// Nothing is swallowed — the real `developer.log` is still called, so DevTools'
/// Logging view is unaffected. When the kill switch is off, only the
/// [LogStore] side no-ops.
///
/// [level] follows the `package:logging` scale that `developer.log` documents
/// (FINE 500 / INFO 800 / WARNING 900 / SEVERE 1000) and is mapped onto
/// [LogLevel] with [debugLevelFromSeverity]. [name] becomes the entry's tag.
void debugLog(
  String message, {
  DateTime? time,
  int? sequenceNumber,
  int level = 0,
  String name = '',
  Zone? zone,
  Object? error,
  StackTrace? stackTrace,
}) {
  developer.log(
    message,
    time: time,
    sequenceNumber: sequenceNumber,
    level: level,
    name: name,
    zone: zone,
    error: error,
    stackTrace: stackTrace,
  );
  LogStore.instance.log(
    message,
    // `log()` defaults level to 0, which is *not* "debug" on the logging scale —
    // it means "unset". Treat it as debug rather than mapping 0 to something
    // louder than the caller intended.
    level: debugLevelFromSeverity(level),
    tag: name.isEmpty ? null : name,
    error: error,
    stackTrace: stackTrace,
  );
}

/// [debugLog] under the name `log`, so swapping `import 'dart:developer'` for
/// this package needs no call-site edits.
///
/// Import with a prefix if it collides with another `log` in scope (`dart:math`
/// exports one too).
const log = debugLog;

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
