import 'package:devtray/devtray.dart';

import 'log_session_loader.dart';

/// Adapts [LogSessionLoader] to the Logs page's [LogSessionSource].
///
/// The page can't take a [LogSessionLoader] directly — that would put `dart:io`
/// in the core's import graph, which is the whole reason this package exists.
/// This is the thin translation between the two.
///
/// ```dart
/// LogsDebugPage(sessionSource: DevtrayFileSessions(await LogSessionLoader.open()))
/// ```
class DevtrayFileSessions extends LogSessionSource {
  final LogSessionLoader loader;

  const DevtrayFileSessions(this.loader);

  @override
  Future<List<LogSessionInfo>> list() async {
    final sessions = await loader.list();

    return [
      for (final s in sessions)
        LogSessionInfo(
          // The path is the id: stable, unique, and what [_sessionFor] needs to
          // find the file again without holding the list in memory.
          id: s.path,
          label: s.name,
          detail: s.sizeLabel,
          recordedAt: s.modified,
        ),
    ];
  }

  @override
  Future<List<LogEntry>> load(LogSessionInfo session) async {
    final file = await _sessionFor(session);
    return file == null ? const [] : loader.load(file);
  }

  @override
  bool get canDelete => true;

  @override
  Future<void> delete(LogSessionInfo session) async {
    final file = await _sessionFor(session);
    if (file != null) await loader.delete(file);
  }

  @override
  Future<void> deleteAll() => loader.deleteAll();

  /// Re-resolves the [LogSession] behind an id.
  ///
  /// Looked up rather than cached because the sink prunes files as it runs: a
  /// session listed a minute ago may be gone, and re-reading the directory is
  /// how that surfaces as "nothing there" instead of a stale handle.
  Future<LogSession?> _sessionFor(LogSessionInfo info) async {
    final sessions = await loader.list();
    for (final s in sessions) {
      if (s.path == info.id) return s;
    }
    return null;
  }
}
