import 'dart:io';

import 'package:devtray/devtray.dart';

import 'file_log_sink.dart';
import 'file_network_sink.dart';

/// One saved run of requests on disk.
class NetworkSession {
  final String path;

  /// The run's start time, as the filename encodes it.
  final String name;

  final DateTime modified;
  final int bytes;

  const NetworkSession({
    required this.path,
    required this.name,
    required this.modified,
    required this.bytes,
  });

  String get sizeLabel {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Reads past runs written by [FileNetworkSink].
///
/// ```dart
/// final loader = await NetworkSessionLoader.open();
/// final sessions = await loader.list();
/// final requests = await loader.load(sessions.first);
/// ```
class NetworkSessionLoader {
  final Directory directory;

  const NetworkSessionLoader(this.directory);

  /// Opens a loader over the directory [FileNetworkSink] writes to.
  ///
  /// Must be given the **same** [location] as the sink, or it will look in the
  /// wrong place and find nothing.
  static Future<NetworkSessionLoader> open({
    LogFileLocation location = LogFileLocation.cache,
    Directory? directory,
  }) async {
    if (directory != null) return NetworkSessionLoader(directory);

    // Round-trips through the sink so the path logic lives in exactly one
    // place — a loader looking somewhere the writer never wrote is a silent,
    // confusing failure. `maxFiles` is enormous so merely opening a loader
    // cannot prune the runs it is about to list.
    final sink = await FileNetworkSink.open(location: location, maxFiles: 1 << 30);
    return NetworkSessionLoader(sink.directory);
  }

  /// Available sessions, newest first.
  Future<List<NetworkSession>> list() async {
    final files = await FileNetworkSink.listRequestFiles(directory);

    return [
      for (final file in files)
        NetworkSession(
          path: file.path,
          name: _nameOf(file),
          modified: file.statSync().modified,
          bytes: file.statSync().size,
        ),
    ];
  }

  /// That session's requests, newest first — matching [DevtrayNet.entries], so
  /// a page renders either without knowing which it has.
  Future<List<NetworkLogEntry>> load(NetworkSession session) async {
    final file = File(session.path);
    if (!await file.exists()) return const [];

    // Written oldest-first, shown newest-first.
    return parseNetworkEntries(await file.readAsString()).reversed.toList();
  }

  Future<void> delete(NetworkSession session) async {
    final file = File(session.path);
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteAll() async {
    for (final file in await FileNetworkSink.listRequestFiles(directory)) {
      try {
        await file.delete();
      } catch (_) {
        // A file we can't delete is not worth failing the whole sweep over.
      }
    }
  }

  /// A readable run name from the filename stamp.
  static String _nameOf(File file) {
    final base = file.uri.pathSegments.last
        .replaceAll(FileNetworkSink.extension, '')
        .replaceFirst('requests_', '');

    final part = base.indexOf('_part');
    final stamp = part == -1 ? base : base.substring(0, part);
    final suffix = part == -1 ? '' : ' · part ${base.substring(part + 5)}';

    // The stamp is an ISO-8601 string with its colons and dots substituted for
    // filename legality; put them back for display.
    final restored = stamp.replaceFirst(
      RegExp(r'T(\d{2})-(\d{2})-(\d{2})-(\d+)'),
      r'T$1:$2:$3',
    );
    final parsed = DateTime.tryParse(restored);
    if (parsed == null) return '$stamp$suffix';

    String two(int v) => v.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}:${two(parsed.second)}$suffix';
  }
}

/// Adapts [NetworkSessionLoader] to the core's [NetworkSessionSource].
///
/// The core can't take a loader directly — that would put `dart:io` in its
/// import graph, which is the whole reason this package exists.
///
/// ```dart
/// DevtrayFileRequestSessions(await NetworkSessionLoader.open())
/// ```
class DevtrayFileRequestSessions extends NetworkSessionSource {
  final NetworkSessionLoader loader;

  const DevtrayFileRequestSessions(this.loader);

  @override
  Future<List<NetworkSessionInfo>> list() async {
    final sessions = await loader.list();

    return [
      for (final s in sessions)
        NetworkSessionInfo(
          // The path is the id: stable, unique, and enough to find the file
          // again without holding the list in memory.
          id: s.path,
          label: s.name,
          detail: s.sizeLabel,
          recordedAt: s.modified,
        ),
    ];
  }

  @override
  Future<List<NetworkLogEntry>> load(NetworkSessionInfo session) async {
    final file = await _sessionFor(session);
    return file == null ? const [] : loader.load(file);
  }

  @override
  bool get canDelete => true;

  @override
  Future<void> delete(NetworkSessionInfo session) async {
    final file = await _sessionFor(session);
    if (file != null) await loader.delete(file);
  }

  @override
  Future<void> deleteAll() => loader.deleteAll();

  /// Re-resolves the session behind an id.
  ///
  /// Looked up rather than cached because the sink prunes as it runs: a session
  /// listed a minute ago may be gone, and re-reading the directory is how that
  /// surfaces as "nothing there" instead of a stale handle.
  Future<NetworkSession?> _sessionFor(NetworkSessionInfo info) async {
    final sessions = await loader.list();
    for (final s in sessions) {
      if (s.path == info.id) return s;
    }
    return null;
  }
}
