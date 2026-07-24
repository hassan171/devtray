import 'dart:convert';
import 'dart:io';

import 'package:devtray/devtray.dart';
import 'package:path_provider/path_provider.dart';

import 'file_log_sink.dart';

/// Writes captured requests to a file, one JSON object per line.
///
/// The network counterpart to [FileLogSink], and the same shape: one file per
/// app run, rotation past [maxBytes], and old *sessions* pruned whole rather
/// than file-by-file.
///
/// ```dart
/// runDebugApp(
///   () => const MyApp(),
///   configure: (d) => d..networkToAsync(() => FileNetworkSink.open()),
/// );
/// ```
///
/// ## A separate file from the logs
///
/// Requests land in `requests_<start>.devtraynet`, alongside the run's
/// `session_<start>.devtraylog`. Two files rather than one stream of tagged
/// records, because every reader then parses one shape: the log session picker
/// would otherwise have to skip records it cannot render, and `parseLogEntries`
/// would have to tolerate lines that are not log entries at all.
///
/// The session stamp is shared, so a run's log file and request file sort
/// together and are recognisably the same run.
///
/// ## When a request is written
///
/// On completion, and — for anything still in flight — when the app is
/// backgrounded. See [DevtrayNetExport]; the timing is its decision, not this
/// sink's.
class FileNetworkSink extends NetworkSink {
  /// The file currently being appended to.
  File get file => _current;
  File _current;

  /// Where session files live.
  final Directory directory;

  /// Roll over to a continuation past this size.
  final int maxBytes;

  /// How many *sessions* to keep.
  final int maxFiles;

  /// Renders one request as a line. Defaults to JSON.
  final String Function(NetworkLogEntry) format;

  /// The run's start stamp, shared by every part of it.
  final String _sessionStamp;
  int _part = 1;

  FileNetworkSink._({
    required File file,
    required this.directory,
    required this.maxBytes,
    required this.maxFiles,
    required this.format,
    required this._sessionStamp,
  }) : _current = file;

  /// File extension for request session files.
  ///
  /// Distinct from [FileLogSink.extension] so neither loader can mistake the
  /// other's files for its own.
  static const String extension = '.devtraynet';

  /// Opens a sink writing to a new session file.
  ///
  /// [directory] overrides the location entirely — mostly for tests, which
  /// can't call `path_provider`.
  static Future<FileNetworkSink> open({
    LogFileLocation location = LogFileLocation.cache,
    Directory? directory,
    int maxBytes = 5 * 1024 * 1024,
    int maxFiles = 5,
    String Function(NetworkLogEntry)? format,
  }) async {
    final dir = directory ?? await _resolveDirectory(location);
    await dir.create(recursive: true);

    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    final sink = FileNetworkSink._(
      file: File('${dir.path}${Platform.pathSeparator}requests_$stamp$extension'),
      directory: dir,
      maxBytes: maxBytes,
      maxFiles: maxFiles,
      format: format ?? formatNetworkEntryAsJson,
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
  Future<void> write(List<NetworkLogEntry> batch) async {
    if (batch.isEmpty) return;

    final text = '${batch.map(format).join('\n')}\n';

    // Append rather than hold a handle open: an open write handle is exactly
    // what is lost when the process dies, which is the case this exists for.
    await _current.writeAsString(text, mode: FileMode.append, flush: true);

    if (await _current.length() > maxBytes) await _rotate();
  }

  /// Starts a continuation, keeping the session's start stamp so every part of
  /// one run sorts together and prunes together.
  Future<void> _rotate() async {
    _part++;
    _current = File('${directory.path}${Platform.pathSeparator}requests_${_sessionStamp}_part$_part$extension');
    await _prune();
  }

  /// Deletes the oldest sessions past [maxFiles], whole runs at a time.
  Future<void> _prune() async {
    try {
      final files = await listRequestFiles(directory);

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
            // Pruning is housekeeping, not the job.
          }
        }
      }
    } catch (_) {
      // Same.
    }
  }

  /// The session start stamp in a filename, shared by every part of a run.
  static String _stampOf(File file) {
    final base = file.uri.pathSegments.last.replaceAll(extension, '').replaceFirst('requests_', '');
    final part = base.indexOf('_part');
    return part == -1 ? base : base.substring(0, part);
  }

  /// Request session files in [directory], newest first.
  static Future<List<File>> listRequestFiles(Directory directory) async {
    if (!await directory.exists()) return [];

    final files = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith(extension)) files.add(entity);
    }
    // Stamps are sortable by name, so this needs no stat calls.
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }
}

/// One request as a JSON line.
String formatNetworkEntryAsJson(NetworkLogEntry entry) => jsonEncode(entry.toJson());

/// Parses request lines written by [formatNetworkEntryAsJson].
///
/// Damaged lines are skipped rather than failing the file: the runs worth
/// reading are often the ones the app died halfway through writing.
List<NetworkLogEntry> parseNetworkEntries(String contents) {
  final entries = <NetworkLogEntry>[];

  for (final line in const LineSplitter().convert(contents)) {
    if (line.trim().isEmpty) continue;
    try {
      final json = jsonDecode(line);
      if (json is! Map) continue;
      entries.add(NetworkLogEntry.fromJson(Map<String, Object?>.from(json)));
    } catch (_) {
      // A truncated final line is the expected case, not an error.
    }
  }

  return entries;
}
