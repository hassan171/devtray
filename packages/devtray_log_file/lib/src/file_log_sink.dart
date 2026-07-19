import 'dart:async';
import 'dart:io';

import 'package:devtray/devtray.dart';
import 'package:path_provider/path_provider.dart';

/// Where log files are kept.
///
/// The distinction matters more than it looks. On iOS, documents are backed up
/// to iCloud and visible in the Files app if the app opts in; caches are not
/// backed up and the OS may delete them under storage pressure. Logs are
/// diagnostic scratch data, so [cache] is the right default — but an app whose
/// whole point is exporting a log the user can find wants [documents], and
/// that's the app's call, not this package's.
enum LogFileLocation {
  /// `getApplicationCacheDirectory()` — not backed up, OS-evictable. Default.
  cache,

  /// `getApplicationDocumentsDirectory()` — backed up, survives, may be
  /// user-visible. For logs the user is meant to find and send on.
  documents,

  /// `getTemporaryDirectory()` — the most aggressively cleared.
  temporary,
}

/// Writes captured logs to rotating files on disk.
///
/// ```dart
/// DevtrayExport.instance.addSink(await FileLogSink.open());
/// ```
///
/// That's the whole setup. Each app run gets its own file, older files are
/// pruned past [maxFiles], and a file that grows past [maxBytes] is rolled over
/// so a chatty session can't fill the disk.
///
/// ## Why one file per session rather than one rolling file
///
/// The question a log answers is almost always "what happened in the run that
/// broke", and a single rolling file makes you find the boundaries yourself. A
/// file per run means [listSessions] can offer you *runs*, and loading one back
/// gives you exactly that run — which is what [LogSessionLoader] and the Logs
/// page's session browser are built on.
///
/// The cost is that a crash-restart loop makes files quickly. [maxFiles] bounds
/// it: oldest are deleted first.
class FileLogSink extends LogSink {
  /// The file currently being appended to.
  final File file;

  /// Directory holding this and previous sessions' files.
  final Directory directory;

  /// Roll over to a new file past this size. Checked per batch, not per line,
  /// so a file can overshoot by at most one batch.
  final int maxBytes;

  /// How many session files to keep. Oldest are deleted first, after a
  /// rotation and on [open].
  final int maxFiles;

  /// How each entry is rendered.
  ///
  /// Defaults to [formatLogEntryAsJson] — JSON Lines, which [LogSessionLoader]
  /// can read back. Swap in [formatLogEntryAsText] for a file meant for human
  /// eyes only; the loader won't be able to parse it.
  final String Function(LogEntry) format;

  File _current;

  /// Timestamp this session started, as it appears in every one of its
  /// filenames. Continuations reuse it so all parts of one run sort together
  /// and are recognisably the same run — see [_rotate].
  final String _sessionStamp;

  /// Which part of the session [_current] is. 1 is the original file.
  int _part = 1;

  FileLogSink._({
    required this.file,
    required this.directory,
    required this.maxBytes,
    required this.maxFiles,
    required this.format,
    required this._sessionStamp,
  }) : _current = file;

  /// File extension used for session files. Also how [listSessions] recognises
  /// them, so nothing else in the directory is mistaken for a log.
  static const String extension = '.devtraylog';

  /// Opens a sink writing to a new session file.
  ///
  /// [directory] overrides the location entirely — mostly for tests, which
  /// can't call `path_provider`. Otherwise [location] picks the base directory
  /// and files land in a `devtray_logs/` subdirectory of it.
  static Future<FileLogSink> open({
    LogFileLocation location = LogFileLocation.cache,
    Directory? directory,
    int maxBytes = 5 * 1024 * 1024,
    int maxFiles = 5,
    String Function(LogEntry)? format,
  }) async {
    final dir = directory ?? await _resolveDirectory(location);
    await dir.create(recursive: true);

    // Sortable-by-name timestamps, so listing and pruning are lexicographic and
    // never have to stat every file. Colons are illegal in Windows filenames,
    // hence the substitution rather than a raw ISO-8601 string.
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    final sink = FileLogSink._(
      file: File('${dir.path}${Platform.pathSeparator}session_$stamp$extension'),
      directory: dir,
      maxBytes: maxBytes,
      maxFiles: maxFiles,
      format: format ?? formatLogEntryAsJson,
      sessionStamp: stamp,
    );

    await sink._prune();
    return sink;
  }

  static Future<Directory> _resolveDirectory(LogFileLocation location) async {
    final base = switch (location) {
      LogFileLocation.cache => await getApplicationCacheDirectory(),
      LogFileLocation.documents => await getApplicationDocumentsDirectory(),
      LogFileLocation.temporary => await getTemporaryDirectory(),
    };
    return Directory('${base.path}${Platform.pathSeparator}devtray_logs');
  }

  @override
  String get name => 'File (${_current.uri.pathSegments.last})';

  @override
  Future<void> write(List<LogEntry> batch) async {
    if (batch.isEmpty) return;

    final text = '${batch.map(format).join('\n')}\n';

    // Append rather than hold a handle open across the app's lifetime: an open
    // write handle is exactly what gets lost when the process dies, and the
    // whole point of persisting logs is surviving that.
    await _current.writeAsString(text, mode: FileMode.append, flush: true);

    if (await _current.length() > maxBytes) await _rotate();
  }

  /// Starts a new file. The current one is left in place — it's a completed
  /// part of this session, and deleting it would defeat the point.
  ///
  /// The continuation keeps the session's **start** stamp and adds a part
  /// number, rather than stamping itself with the time of the rollover. Two
  /// files from one run stamped minutes apart look like two unrelated runs,
  /// which is exactly the thing a session-per-file layout exists to avoid.
  /// Sharing the stamp also makes the parts sort adjacently, which is what
  /// [_prune] relies on to evict a whole run at a time.
  Future<void> _rotate() async {
    _part++;
    _current = File('${directory.path}${Platform.pathSeparator}session_${_sessionStamp}_part$_part$extension');
    await _prune();
  }

  /// Deletes the oldest *sessions* past [maxFiles].
  ///
  /// Grouped by session rather than counting files, because a run that rolled
  /// over occupies several. Pruning file-by-file could delete the first half of
  /// a run and keep the second — leaving a log that starts mid-story with
  /// nothing to say a beginning ever existed. A session is evicted whole or not
  /// at all.
  Future<void> _prune() async {
    try {
      final files = await listSessionFiles(directory);

      // Session start stamp → its parts. Insertion order follows
      // listSessionFiles (newest first), and parts of one run share a stamp.
      final sessions = <String, List<File>>{};
      for (final file in files) {
        sessions.putIfAbsent(_stampOf(file), () => []).add(file);
      }

      if (sessions.length <= maxFiles) return;

      for (final stale in sessions.keys.skip(maxFiles).toList()) {
        for (final file in sessions[stale]!) {
          try {
            await file.delete();
          } catch (_) {
            // A file we can't delete (open elsewhere, permissions) is not worth
            // failing the sink over — the cap is just soft this run.
          }
        }
      }
    } catch (_) {
      // Same reasoning: pruning is housekeeping, not the job.
    }
  }

  /// The session start stamp encoded in a filename — shared by every part of
  /// one run, which is what groups them.
  static String _stampOf(File file) {
    final base = file.uri.pathSegments.last.replaceAll(extension, '').replaceFirst('session_', '');
    // `2026-07-19T14-30-00_part2` → `2026-07-19T14-30-00`
    final marker = base.indexOf('_part');
    return marker == -1 ? base : base.substring(0, marker);
  }

  /// Session files in [directory], newest first.
  static Future<List<File>> listSessionFiles(Directory directory) async {
    if (!await directory.exists()) return [];

    final files = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith(extension)) files.add(entity);
    }

    // By name, which encodes the timestamp — no stat() per file.
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  @override
  Future<void> close() async {
    // Nothing held open — each write appends and flushes. Deliberate: see
    // [write].
  }
}
