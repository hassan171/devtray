import 'package:flutter/material.dart';

import '../../core/devtray_theme.dart';
import '../../core/debug_text_styles.dart';
import '../devtray_export.dart';

/// Picks a saved run to load into the Logs page.
///
/// ```dart
/// final session = await LogSessionPicker.show(context, source);
///
/// Generic over what a session holds: logs and requests are separate files with
/// separate sources, but browsing them is the same interaction, so one picker
/// serves both rather than two that drift apart.
/// ```
///
/// Returns the chosen session, or null if dismissed. Deleting from here is
/// deliberate: the file is the only copy, so removing it belongs behind an
/// explicit confirmation in the place you can see what you're removing — not on
/// a toolbar button next to "clear logs", which means something else entirely.
class LogSessionPicker<T extends DevtraySessionInfo> extends StatefulWidget {
  final DevtraySessionSource<T> source;

  const LogSessionPicker({super.key, required this.source});

  static Future<T?> show<T extends DevtraySessionInfo>(BuildContext context, DevtraySessionSource<T> source) {
    final theme = DevtrayTheme.of(context);

    return showDialog<T>(
      context: context,
      builder: (_) => DevtrayThemeScope(
        // The dialog is a new route, outside this page's theme scope — without
        // re-providing it the picker would render in Material defaults while
        // the panel behind it stays dark.
        theme: theme,
        child: Dialog(
          backgroundColor: theme.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
            child: LogSessionPicker<T>(source: source),
          ),
        ),
      ),
    );
  }

  @override
  State<LogSessionPicker<T>> createState() => _LogSessionPickerState<T>();
}

class _LogSessionPickerState<T extends DevtraySessionInfo> extends State<LogSessionPicker<T>> {
  List<T>? _sessions;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sessions = await widget.source.list();
      if (mounted) setState(() => _sessions = sessions);
    } catch (e) {
      // A source that can't list (a missing directory, a permissions problem)
      // should say so rather than showing an empty list that reads as "no
      // sessions have been saved".
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _delete(T session) async {
    final confirmed = await _confirm(
      title: 'Delete this session?',
      message: '${session.label} will be removed from disk. This cannot be undone.',
    );
    if (!confirmed) return;

    await widget.source.delete(session);
    await _load();
  }

  Future<void> _deleteAll() async {
    final confirmed = await _confirm(
      title: 'Delete every saved session?',
      message: '${_sessions?.length ?? 0} files will be removed from disk. This cannot be undone.',
    );
    if (!confirmed) return;

    await widget.source.deleteAll();
    await _load();
  }

  Future<bool> _confirm({required String title, required String message}) async {
    final t = DevtrayTheme.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => DevtrayThemeScope(
        theme: t,
        child: AlertDialog(
          backgroundColor: t.background,
          title: Text(title, style: TextStyle(fontSize: 14, color: t.text)),
          content: Text(message, style: TextStyle(fontSize: 12, color: t.textMuted)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: t.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Delete', style: TextStyle(color: t.error)),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final sessions = _sessions;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
          child: Row(
            children: [
              Icon(Icons.history, size: 16, color: t.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Saved sessions',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.text),
                ),
              ),
              if (widget.source.canDelete && (sessions?.isNotEmpty ?? false))
                IconButton(
                  tooltip: 'Delete all',
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(Icons.delete_sweep_outlined, size: 16, color: t.error),
                  onPressed: _deleteAll,
                ),
              IconButton(
                tooltip: 'Close',
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(Icons.close, size: 16, color: t.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Divider(color: t.border, height: 1),
        Flexible(child: _buildBody(t, sessions)),
      ],
    );
  }

  Widget _buildBody(DevtrayTheme t, List<T>? sessions) {
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Could not read saved sessions',
        detail: '$_error',
        color: t.error,
      );
    }

    if (sessions == null) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: t.textMuted)),
        ),
      );
    }

    if (sessions.isEmpty) {
      return _Message(
        icon: Icons.folder_off_outlined,
        title: 'No saved sessions',
        // Says what to do about it, rather than leaving an empty box. The usual
        // cause is that no sink was ever added.
        detail: 'Sessions appear here once a log sink is writing them —\n'
            'DevtrayExport.instance.addSink(await FileLogSink.open()).',
        color: t.textMuted,
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: sessions.length,
      itemBuilder: (context, i) {
        final session = sessions[i];

        return ListTile(
          dense: true,
          leading: Icon(Icons.description_outlined, size: 16, color: t.textMuted),
          title: Text(
            session.label,
            style: DebugTextStyles.debugMono(color: t.text, fontSize: 12),
          ),
          subtitle: session.detail == null
              ? null
              : Text(session.detail!, style: TextStyle(fontSize: 10, color: t.textMuted)),
          trailing: widget.source.canDelete
              ? IconButton(
                  tooltip: 'Delete',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(Icons.delete_outline, size: 15, color: t.textMuted),
                  onPressed: () => _delete(session),
                )
              : null,
          onTap: () => Navigator.of(context).pop(session),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  const _Message({required this.icon, required this.title, required this.detail, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: color.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
