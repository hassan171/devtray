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
/// LogExporter.instance.addSink(await FileLogSink.open());
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

  FileLogSink._({
    required this.file,
    required this.directory,
    required this.maxBytes,
    required this.maxFiles,
    required this.format,
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
  Future<void> _rotate() async {
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    _current = File('${directory.path}${Platform.pathSeparator}session_${stamp}_cont$extension');
    await _prune();
  }

  /// Deletes the oldest files past [maxFiles].
  Future<void> _prune() async {
    try {
      final files = await listSessionFiles(directory);
      if (files.length <= maxFiles) return;

      // listSessionFiles is newest-first, so everything past the cap is old.
      for (final stale in files.skip(maxFiles)) {
        try {
          await stale.delete();
        } catch (_) {
          // A file we can't delete (open elsewhere, permissions) is not worth
          // failing the sink over — it just means the cap is soft this run.
        }
      }
    } catch (_) {
      // Same reasoning: pruning is housekeeping, not the job.
    }
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
