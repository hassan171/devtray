import 'package:flutter/material.dart';

import '../core/debug_overlay_theme.dart';
import '../core/debug_page.dart';
import '../widgets/debug_search_bar.dart';
import 'components/storage_value_editor.dart';
import 'debug_storage_adapter.dart';

/// Browse — and edit — key/value storage while the app is running.
///
/// Editing is the point: flip a feature flag, expire a token, clear an
/// onboarding-seen bool, all without rebuilding.
///
/// ```dart
/// StorageDebugPage(adapters: [
///   const SharedPreferencesStorageAdapter(),
///   MyHiveAdapter(),   // see DebugStorageAdapter
/// ])
/// ```
///
/// Editing is per-field: tap Edit, change the value, tap Save. A value is
/// written back as the **same type** it already was, and bad input is rejected
/// without touching the store — see [StorageValueEditor].
///
/// Set `writable => false` on an adapter for a store you only want to read.
class StorageDebugPage extends DebugPage {
  final List<DebugStorageAdapter> adapters;

  const StorageDebugPage({required this.adapters});

  @override
  String get title => 'Storage';

  @override
  IconData? get icon => Icons.storage;

  @override
  Widget build(BuildContext context) => _StorageView(adapters: adapters);
}

class _StorageView extends StatefulWidget {
  final List<DebugStorageAdapter> adapters;
  const _StorageView({required this.adapters});

  @override
  State<_StorageView> createState() => _StorageViewState();
}

class _StorageViewState extends State<_StorageView> {
  String _search = '';

  late Future<List<_Section>> _future = _load();

  Future<List<_Section>> _load() async {
    return Future.wait(
      widget.adapters.map((a) async {
        try {
          return _Section(adapter: a, values: await a.readAll());
        } catch (e) {
          return _Section(adapter: a, values: const {}, error: e.toString());
        }
      }),
    );
  }

  void _refresh() {
    // Two traps here. Build the future OUTSIDE setState (no async work inside
    // it), AND use a block body — `setState(() => _future = next)` *returns*
    // next, and Flutter asserts on a closure that returns a Future regardless of
    // whether any async work actually happened in it.
    final next = _load();
    setState(() {
      _future = next;
    });
  }

  Future<void> _write(DebugStorageAdapter adapter, String key, Object? value) async {
    await adapter.write(key, value);
    _refresh();
  }

  Future<void> _delete(DebugStorageAdapter adapter, String key) async {
    await adapter.delete(key);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DebugSearchBar(
          hintText: 'Search keys',
          total: 0,
          onChanged: (v) => setState(() => _search = v),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: Icon(Icons.refresh, size: 18, color: t.text),
              onPressed: _refresh,
            ),
          ],
        ),
        Expanded(
          child: FutureBuilder<List<_Section>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(child: CircularProgressIndicator(color: t.accent));
              }

              final sections = snapshot.data ?? const <_Section>[];
              final q = _search.toLowerCase();

              return ListView(
                children: [
                  for (final section in sections)
                    _SectionView(
                      section: section,
                      query: q,
                      theme: t,
                      onWrite: (k, v) => _write(section.adapter, k, v),
                      onDelete: (k) => _delete(section.adapter, k),
                    ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Section {
  final DebugStorageAdapter adapter;
  final Map<String, Object?> values;
  final String? error;

  const _Section({required this.adapter, required this.values, this.error});
}

class _SectionView extends StatelessWidget {
  final _Section section;
  final String query;
  final DebugOverlayTheme theme;
  final void Function(String key, Object? value) onWrite;
  final void Function(String key) onDelete;

  const _SectionView({
    required this.section,
    required this.query,
    required this.theme,
    required this.onWrite,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final keys = section.values.keys.where((k) => query.isEmpty || k.toLowerCase().contains(query)).toList()..sort();

    // Editing is per-field (tap Edit, then Save), which is a deliberate enough
    // two-step on its own — no global lock on top of it.
    final canEdit = section.adapter.writable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              section.adapter.name,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.accent),
            ),
            const SizedBox(width: 8),
            Text('${keys.length}', style: TextStyle(fontSize: 11, color: theme.textMuted)),
            if (!section.adapter.writable) ...[
              const SizedBox(width: 8),
              Text('read-only', style: TextStyle(fontSize: 10, color: theme.textMuted)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        if (section.error != null)
          Text(
            'Could not read: ${section.error}',
            style: TextStyle(fontSize: 11, color: theme.error),
          )
        else if (keys.isEmpty)
          Text(
            query.isEmpty ? 'Empty' : 'No matching keys',
            style: TextStyle(fontSize: 11, color: theme.textMuted),
          )
        else
          for (final key in keys)
            StorageValueEditor(
              storageKey: key,
              value: section.values[key],
              canEdit: canEdit,
              onWrite: (v) => onWrite(key, v),
              onDelete: () => onDelete(key),
            ),
      ],
    );
  }
}
