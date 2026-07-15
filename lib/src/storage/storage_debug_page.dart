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
/// With more than one adapter, the page opens on a **list of stores** (name,
/// key-count, read-only badge); tap one to drill into its keys, back arrow to
/// return. A single adapter skips the list and opens straight into its keys —
/// there's nothing to choose. Search scopes to the store you're in.
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

  /// The store currently drilled into, by adapter name (stable across reloads).
  /// Null means the store list is showing. With a single adapter this is pinned
  /// to it, so the list is skipped entirely.
  String? _selectedName;

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
    // A lone adapter has no list to choose from — open straight into it.
    if (widget.adapters.length == 1) _selectedName = widget.adapters.single.name;
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

  void _open(String name) {
    // Fresh store, fresh scroll position — otherwise the offset from the last
    // store carries over into this one.
    _search = '';
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _selectedName = name);
  }

  void _back() => setState(() => _selectedName = null);

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final sections = _sections;

    if (sections == null) {
      // Only on the very first load — a save never returns here.
      return Center(child: CircularProgressIndicator(color: t.accent));
    }

    final selected = _selectedName == null ? null : sections.where((s) => s.adapter.name == _selectedName).firstOrNull;

    if (selected == null) return _StoreList(sections: sections, theme: t, onOpen: _open, onRefresh: _refresh);

    return _StoreDetail(
      section: selected,
      theme: t,
      search: _search,
      scroll: _scroll,
      // A single adapter has no list to go back to — hide the back arrow.
      onBack: widget.adapters.length == 1 ? null : _back,
      onSearch: (v) => setState(() => _search = v),
      onRefresh: _refresh,
      onWrite: _write,
      onDelete: _delete,
    );
  }
}

/// The list of stores — the first screen when there's more than one adapter.
class _StoreList extends StatelessWidget {
  final List<_Section> sections;
  final DebugOverlayTheme theme;
  final ValueChanged<String> onOpen;
  final Future<void> Function() onRefresh;

  const _StoreList({required this.sections, required this.theme, required this.onOpen, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Stores', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.text)),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              icon: Icon(Icons.refresh, size: 18, color: theme.text),
              onPressed: onRefresh,
            ),
          ],
        ),
        Divider(color: theme.border),
        Expanded(
          child: ListView.builder(
            itemCount: sections.length,
            itemBuilder: (context, i) {
              final s = sections[i];
              return InkWell(
                onTap: () => onOpen(s.adapter.name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.border, width: 0.5))),
                  child: Row(
                    children: [
                      Icon(Icons.folder_outlined, size: 18, color: theme.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.adapter.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.text),
                        ),
                      ),
                      if (!s.adapter.writable) ...[
                        Text('read-only', style: TextStyle(fontSize: 10, color: theme.textMuted)),
                        const SizedBox(width: 8),
                      ],
                      if (s.error != null)
                        Icon(Icons.error_outline, size: 16, color: theme.error)
                      else
                        Text('${s.values.length}', style: TextStyle(fontSize: 12, color: theme.textMuted)),
                      Icon(Icons.chevron_right, size: 18, color: theme.textMuted),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One store's keys — the drilled-in view. Search + refresh scope to it, and the
/// lazy `ListView.builder` keeps a 1000-key store from building every editor up
/// front.
class _StoreDetail extends StatelessWidget {
  final _Section section;
  final DebugOverlayTheme theme;
  final String search;
  final ScrollController scroll;

  /// Null hides the back arrow (single-adapter case — nowhere to go back to).
  final VoidCallback? onBack;
  final ValueChanged<String> onSearch;
  final Future<void> Function() onRefresh;
  final Future<void> Function(DebugStorageAdapter, String, Object?) onWrite;
  final Future<void> Function(DebugStorageAdapter, String) onDelete;

  const _StoreDetail({
    required this.section,
    required this.theme,
    required this.search,
    required this.scroll,
    required this.onBack,
    required this.onSearch,
    required this.onRefresh,
    required this.onWrite,
    required this.onDelete,
  });

  /// The keys to show — filtered by [search], sorted once. (At 1000 keys, doing
  /// this twice per build is real work.)
  List<String> _keys() {
    if (section.error != null) return const [];
    final q = search.toLowerCase();
    return section.values.keys.where((k) => q.isEmpty || k.toLowerCase().contains(q)).toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final keys = _keys();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (onBack != null)
              IconButton(
                tooltip: 'Back to stores',
                icon: Icon(Icons.arrow_back, size: 18, color: theme.text),
                onPressed: onBack,
              ),
            Flexible(
              child: Text(
                section.adapter.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.text),
              ),
            ),
            const SizedBox(width: 8),
            Text('${section.values.length}', style: TextStyle(fontSize: 11, color: theme.textMuted)),
            if (!section.adapter.writable) ...[
              const SizedBox(width: 8),
              Text('read-only', style: TextStyle(fontSize: 10, color: theme.textMuted)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        DebugSearchBar(
          hintText: 'Search keys',
          total: keys.length,
          onChanged: onSearch,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: Icon(Icons.refresh, size: 18, color: theme.text),
              onPressed: onRefresh,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: section.error != null
              ? _Message('Could not read: ${section.error}', theme: theme, isError: true)
              : keys.isEmpty
                  ? _Message(search.isEmpty ? 'Empty' : 'No matching keys', theme: theme)
                  : ListView.builder(
                      controller: scroll,
                      itemCount: keys.length,
                      itemBuilder: (context, i) {
                        final key = keys[i];
                        return StorageValueEditor(
                          // Keyed by adapter+key so a rebuild doesn't hand a
                          // row's controller to a different key.
                          key: ValueKey('${section.adapter.name}/$key'),
                          storageKey: key,
                          value: section.values[key],
                          canEdit: section.adapter.writable,
                          onWrite: (v) => onWrite(section.adapter, key, v),
                          onDelete: () => onDelete(section.adapter, key),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final DebugOverlayTheme theme;
  final bool isError;

  const _Message(this.text, {required this.theme, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text, style: TextStyle(fontSize: 11, color: isError ? theme.error : theme.textMuted)),
    );
  }
}

class _Section {
  final DebugStorageAdapter adapter;
  final Map<String, Object?> values;
  final String? error;

  const _Section({required this.adapter, required this.values, this.error});
}
