import 'dart:io';

import 'package:devtray/devtray.dart';

import 'file_log_sink.dart';

/// Reads back what [FileLogSink] wrote — the other half of persistence.
///
/// Writing logs you can't get at again is only half a feature. This is what
/// turns a directory of files into something the Logs page can offer you:
/// [list] for "which runs do I have", [load] for "show me that one".
///
/// ```dart
/// final loader = await LogSessionLoader.open();
/// final sessions = await loader.list();
/// final entries = await loader.load(sessions.first);
/// ```
///
/// Loaded entries are plain [LogEntry]s and are deliberately **not** pushed
/// into [LogStore] — see [LogSession]. The Logs page renders them in a separate
/// read-only view.
class LogSessionLoader {
  /// Where session files are read from.
  final Directory directory;

  const LogSessionLoader(this.directory);

  /// Opens a loader over the same directory [FileLogSink.open] writes to.
  ///
  /// [location] must match what the sink was opened with, or you'll be looking
  /// in the wrong place and get an empty list.
  static Future<LogSessionLoader> open({
    LogFileLocation location = LogFileLocation.cache,
    Directory? directory,
  }) async {
    if (directory != null) return LogSessionLoader(directory);

    // Round-trips through the sink so the path logic lives in exactly one
    // place — a loader looking somewhere the writer never wrote is a silent,
    // confusing failure.
    final sink = await FileLogSink.open(location: location, maxFiles: 1 << 30);
    return LogSessionLoader(sink.directory);
  }

  /// Available sessions, newest first.
  Future<List<LogSession>> list() async {
    final files = await FileLogSink.listSessionFiles(directory);

    return [
      for (final file in files)
        LogSession(
          path: file.path,
          name: _displayName(file),
          modified: await _modified(file),
          bytes: await _length(file),
        ),
    ];
  }

  /// Parses one session's entries, newest first.
  ///
  /// Returns empty rather than throwing when the file is gone — a session can
  /// be pruned by a running sink between listing and loading, and that's a
  /// normal race rather than an error worth crashing the page over.
  Future<List<LogEntry>> load(LogSession session) async {
    final file = File(session.path);
    if (!await file.exists()) return const [];

    try {
      return parseLogEntries(await file.readAsString());
    } catch (_) {
      // Unreadable or not text. parseLogEntries already tolerates damage
      // line-by-line, so reaching here means the whole file is unusable.
      return const [];
    }
  }

  /// Deletes a session file.
  Future<void> delete(LogSession session) async {
    final file = File(session.path);
    if (await file.exists()) await file.delete();
  }

  /// Deletes every session file in [directory].
  Future<void> deleteAll() async {
    for (final file in await FileLogSink.listSessionFiles(directory)) {
      try {
        await file.delete();
      } catch (_) {
        // Best effort — a locked file shouldn't abort the rest.
      }
    }
  }

  static Future<DateTime> _modified(File f) async {
    try {
      return await f.lastModified();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  static Future<int> _length(File f) async {
    try {
      return await f.length();
    } catch (_) {
      return 0;
    }
  }

  /// `session_2026-07-19T14-30-00-000.devtraylog` → `2026-07-19 14:30:00`.
  ///
  /// Falls back to the raw filename if it doesn't match the pattern, so a file
  /// someone dropped in by hand still lists rather than showing as blank.
  static String _displayName(File file) {
    final base = file.uri.pathSegments.last.replaceAll(FileLogSink.extension, '');
    final stamp = base.replaceFirst('session_', '').replaceFirst('_cont', '');

    final parts = stamp.split('T');
    if (parts.length != 2) return base;

    final time = parts[1].split('-');
    if (time.length < 3) return base;

    final continued = base.endsWith('_cont') ? ' (continued)' : '';
    return '${parts[0]} ${time[0]}:${time[1]}:${time[2]}$continued';
  }
}

/// One saved run, as offered by [LogSessionLoader.list].
class LogSession {
  /// Absolute path to the file.
  final String path;

  /// Human-readable label — the session's start time, where derivable.
  final String name;

  final DateTime modified;
  final int bytes;

  const LogSession({
    required this.path,
    required this.name,
    required this.modified,
    required this.bytes,
  });

  /// Size as something readable in a list row.
  String get sizeLabel {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
