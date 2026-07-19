import 'dart:async';

import 'package:flutter/material.dart';

import '../core/devtray_theme.dart';
import '../core/debug_page.dart';
import '../core/debug_text_styles.dart';
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
/// there's nothing to choose. Search matches keys **and** values, scoped to
/// the store you're in.
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

  /// Reads one adapter, turning a failure into a section that reports it rather
  /// than taking the whole page down.
  Future<_Section> _readOne(DebugStorageAdapter adapter) async {
    try {
      return _Section(adapter: adapter, values: await adapter.readAll());
    } catch (e) {
      return _Section(adapter: adapter, values: const {}, error: e.toString());
    }
  }

  /// Loads the adapters that actually need loading.
  ///
  /// Only the *selected* store is read. `readAll()` can be genuinely expensive —
  /// the sqflite adapter runs a `SELECT *` per table, Hive decodes every value —
  /// so eagerly reading all of them meant opening the tab pulled the entire
  /// database into memory on the UI isolate, including stores you never looked
  /// at. Unselected adapters get an empty placeholder; the store list only needs
  /// their names.
  Future<List<_Section>> _read() async {
    final selected = _selectedName;

    return Future.wait(
      widget.adapters.map((a) async {
        if (selected != null && a.name != selected) return _Section(adapter: a, values: const {}, loaded: false);
        return _readOne(a);
      }),
    );
  }

  /// Re-reads the selected adapter and swaps the data in place — no spinner
  /// between the write and the reload. The scroll offset is kept by [_scroll].
  Future<void> _refresh() async {
    final next = await _read();
    if (mounted) setState(() => _sections = next);
  }

  /// Re-reads a single adapter after a write to it, leaving the others alone.
  ///
  /// A write only invalidates the store it touched, so re-reading all of them
  /// (which is what this used to do) re-ran every `SELECT *` on every keystroke
  /// of an edit dialog's save.
  Future<void> _refreshOne(DebugStorageAdapter adapter) async {
    final updated = await _readOne(adapter);
    if (!mounted) return;

    setState(() {
      final sections = _sections;
      if (sections == null) return;
      final i = sections.indexWhere((s) => s.adapter.name == adapter.name);
      if (i != -1) sections[i] = updated;
    });
  }

  Future<void> _write(DebugStorageAdapter adapter, String key, Object? value) async {
    await adapter.write(key, value);
    await _refreshOne(adapter);
  }

  Future<void> _delete(DebugStorageAdapter adapter, String key) async {
    await adapter.delete(key);
    await _refreshOne(adapter);
  }

  void _open(String name) {
    // Fresh store, fresh scroll position — otherwise the offset from the last
    // store carries over into this one.
    _search = '';
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _selectedName = name);

    // Stores are read on open, not up front, so this is where the newly
    // selected one actually gets loaded.
    final adapter = widget.adapters.where((a) => a.name == name).firstOrNull;
    if (adapter != null) unawaited(_refreshOne(adapter));
  }

  void _back() => setState(() => _selectedName = null);

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
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
  final DevtrayTheme theme;
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
            Text('Stores', style: DebugTextStyles.label(color: theme.text, fontSize: 12)),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.refresh, size: 16, color: theme.textMuted),
              onPressed: onRefresh,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Divider(color: theme.border, height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: sections.length,
            itemBuilder: (context, i) {
              final s = sections[i];
              final failed = s.error != null;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onOpen(s.adapter.name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: theme.border.withValues(alpha: 0.6), width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          failed ? Icons.error_outline : Icons.folder_outlined,
                          size: 16,
                          color: failed ? theme.error : theme.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.adapter.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.text),
                              ),
                              // An adapter that threw says so here rather than
                              // just showing a bare icon — the other stores keep
                              // working, so the failure needs naming.
                              if (failed)
                                Text(
                                  'Could not read',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10, color: theme.error),
                                ),
                            ],
                          ),
                        ),
                        if (!s.adapter.writable) ...[
                          _MiniTag(text: 'read-only', color: theme.textMuted),
                          const SizedBox(width: 6),
                        ],
                        if (!failed)
                          Text(
                            '${s.values.length}',
                            style: DebugTextStyles.debugMono(color: theme.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        Icon(Icons.chevron_right, size: 16, color: theme.textMuted),
                      ],
                    ),
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
  final DevtrayTheme theme;
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
  /// Keys matching [search] — by key **or** value, sorted once.
  ///
  /// Values are searched as they're rendered (see [storageSearchableText]), so
  /// finding `admin` in a JSON blob or a tag inside a chip list works. Keys
  /// alone would be a poor filter for the case that matters: you usually know
  /// what you're looking *for*, not which key it's under.
  List<String> _keys() {
    if (section.error != null) return const [];
    final q = search.toLowerCase();
    if (q.isEmpty) return section.values.keys.toList()..sort();

    // Against the cached index — see [_Section.searchIndex]. Rendering each
    // value to text here meant re-encoding every Map-shaped value per keystroke.
    final index = section.searchIndex;
    return section.values.keys.where((k) => (index[k] ?? '').contains(q)).toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final keys = _keys();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (onBack != null) ...[
              IconButton(
                tooltip: 'Back to stores',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(Icons.arrow_back, size: 16, color: theme.textMuted),
                onPressed: onBack,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                section.adapter.name,
                overflow: TextOverflow.ellipsis,
                style: DebugTextStyles.label(color: theme.text, fontSize: 12),
              ),
            ),
            if (!section.adapter.writable) ...[
              const SizedBox(width: 8),
              _MiniTag(text: 'read-only', color: theme.textMuted),
            ],
          ],
        ),
        const SizedBox(height: 6),
        DebugSearchBar(
          hintText: 'Search keys and values',
          total: keys.length,
          onChanged: onSearch,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: Icon(Icons.refresh, size: 16, color: theme.textMuted),
              onPressed: onRefresh,
            ),
          ],
        ),
        // What the adapter wants said about this read — a row cap, most often.
        // Sits under the search bar so it's read before the list is trusted as
        // complete.
        if (section.adapter.notice case final notice?) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.info_outline, size: 12, color: theme.warning),
              const SizedBox(width: 4),
              Expanded(
                child: Text(notice, style: TextStyle(fontSize: 10, color: theme.warning)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Expanded(
          child: section.error != null
              ? _StorageMessage(
                  icon: Icons.error_outline,
                  title: 'Could not read this store',
                  // The adapter's own message — it's the only thing that says
                  // *why*, and it's usually the actual bug.
                  detail: section.error!,
                  theme: theme,
                  isError: true,
                )
              : keys.isEmpty
                  ? _StorageMessage(
                      icon: search.isEmpty ? Icons.inbox_outlined : Icons.search_off,
                      title: search.isEmpty ? 'This store is empty' : 'No matches',
                      detail: search.isEmpty ? 'Nothing has been written to it yet.' : 'Nothing matches "$search".',
                      theme: theme,
                    )
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

/// A small square marker — the read-only flag on a store.
class _MiniTag extends StatelessWidget {
  final String text;
  final Color color;

  const _MiniTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: DebugTextStyles.label(color: color, fontSize: 8)),
    );
  }
}

/// The empty / failed state for a store.
///
/// Centred and explained rather than a bare line of grey text in the corner: an
/// empty store and a store that *failed to read* look identical if all you print
/// is a word, and those are very different problems.
class _StorageMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final DevtrayTheme theme;
  final bool isError;

  const _StorageMessage({
    required this.icon,
    required this.title,
    required this.detail,
    required this.theme,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = isError ? theme.error : theme.textMuted;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: tint.withValues(alpha: 0.6)),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isError ? theme.error : theme.text),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: theme.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section {
  final DebugStorageAdapter adapter;
  final Map<String, Object?> values;
  final String? error;

  /// False for an adapter that hasn't been read yet — it exists in the store
  /// list but its contents were never fetched. See [_StorageViewState._read].
  final bool loaded;

  _Section({required this.adapter, required this.values, this.error, this.loaded = true});

  /// `"key value"`, lowercased, per key — what the search box matches against.
  ///
  /// Built once per load and cached. Rendering a value to text means a
  /// `JsonEncoder.withIndent` pass for anything Map-shaped, and the search ran
  /// it for every key on every keystroke: a 1000-row SQLite table meant 1000
  /// pretty-printed JSON encodes per character typed.
  Map<String, String> get searchIndex => _searchIndex ??= {
        for (final e in values.entries) e.key: storageSearchableText(e.key, e.value).toLowerCase(),
      };
  Map<String, String>? _searchIndex;
}
