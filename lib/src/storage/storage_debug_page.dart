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

  /// The loaded data, held in state rather than rebuilt from a Future on every
  /// change.
  ///
  /// A `FutureBuilder` re-fed after each save flashed its spinner between the
  /// write and the reload. Holding the data means the list just updates.
  List<_Section>? _sections;

  /// **This is what keeps your place after a save.**
  ///
  /// Without an explicit controller the ListView creates its own, which dies with
  /// the widget — so any rebuild that tears the list down restarts it at offset
  /// zero, and editing a key near the bottom of a long store bounced you back to
  /// the top. A controller owned by the State outlives that.
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<List<_Section>> _read() {
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

  /// Re-reads every adapter and swaps the data in place — no spinner between the
  /// write and the reload. The scroll offset is kept by [_scroll].
  Future<void> _refresh() async {
    final next = await _read();
    if (mounted) setState(() => _sections = next);
  }

  Future<void> _write(DebugStorageAdapter adapter, String key, Object? value) async {
    await adapter.write(key, value);
    await _refresh();
  }

  Future<void> _delete(DebugStorageAdapter adapter, String key) async {
    await adapter.delete(key);
    await _refresh();
  }

  /// Flattens the sections into a single list of rows — a header per adapter,
  /// then one row per key.
  ///
  /// This is what lets the page use `ListView.builder`. Nesting a Column of rows
  /// per section inside a plain `ListView(children: [...])` builds **every** row
  /// eagerly — with 1000 keys that's 1000 stateful editors, each with its own
  /// TextEditingController, constructed before the first frame paints. Opening
  /// the tab visibly froze.
  List<_Row> _rows(List<_Section> sections) {
    final query = _search.toLowerCase();
    final rows = <_Row>[];

    for (final section in sections) {
      rows.add(_HeaderRow(section));

      if (section.error != null) {
        rows.add(_MessageRow('Could not read: ${section.error}', isError: true));
        continue;
      }

      // Filter and sort ONCE — at 1000 keys, doing it twice per build is real work.
      final keys = section.values.keys.where((k) => query.isEmpty || k.toLowerCase().contains(query)).toList()..sort();

      if (keys.isEmpty) {
        rows.add(_MessageRow(query.isEmpty ? 'Empty' : 'No matching keys'));
      } else {
        rows.addAll(keys.map((k) => _KeyRow(section, k)));
      }
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final sections = _sections;

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
          child: sections == null
              // Only on the very first load — a save never returns here.
              ? Center(child: CircularProgressIndicator(color: t.accent))
              : Builder(
                  builder: (context) {
                    final rows = _rows(sections);

                    // Lazy: only the rows actually on screen are built.
                    return ListView.builder(
                      controller: _scroll,
                      itemCount: rows.length,
                      itemBuilder: (context, i) => switch (rows[i]) {
                        _HeaderRow(:final section) => _SectionHeader(section: section, theme: t),
                        _MessageRow(:final text, :final isError) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              text,
                              style: TextStyle(fontSize: 11, color: isError ? t.error : t.textMuted),
                            ),
                          ),
                        _KeyRow(:final section, :final key) => StorageValueEditor(
                            // Keyed by adapter+key so a rebuild doesn't hand a
                            // row's controller to a different key.
                            key: ValueKey('${section.adapter.name}/$key'),
                            storageKey: key,
                            value: section.values[key],
                            canEdit: section.adapter.writable,
                            onWrite: (v) => _write(section.adapter, key, v),
                            onDelete: () => _delete(section.adapter, key),
                          ),
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// A flattened row: either a section header, a message, or one key.
sealed class _Row {
  const _Row();
}

class _HeaderRow extends _Row {
  final _Section section;
  const _HeaderRow(this.section);
}

class _MessageRow extends _Row {
  final String text;
  final bool isError;
  const _MessageRow(this.text, {this.isError = false});
}

class _KeyRow extends _Row {
  final _Section section;
  final String key;
  const _KeyRow(this.section, this.key);
}

class _SectionHeader extends StatelessWidget {
  final _Section section;
  final DebugOverlayTheme theme;

  const _SectionHeader({required this.section, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          Text(
            section.adapter.name,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.accent),
          ),
          const SizedBox(width: 8),
          Text('${section.values.length}', style: TextStyle(fontSize: 11, color: theme.textMuted)),
          if (!section.adapter.writable) ...[
            const SizedBox(width: 8),
            Text('read-only', style: TextStyle(fontSize: 10, color: theme.textMuted)),
          ],
        ],
      ),
    );
  }
}

class _Section {
  final DebugStorageAdapter adapter;
  final Map<String, Object?> values;
  final String? error;

  const _Section({required this.adapter, required this.values, this.error});
}
