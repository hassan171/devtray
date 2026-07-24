import 'package:flutter/material.dart';

import '../notes_db.dart';
import 'note_editor_screen.dart';

/// The app's home: notes from SQLite, pinned first.
///
/// Rebuilds on [NotesDb.revision], which every write bumps — **including writes
/// made from the overlay's Storage page**. Edit a note's title in the debug
/// tool and watch it change on the list behind: that's not a demo trick, it's
/// just what happens when the tool reads the store your app already owns.
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<int>(
        valueListenable: NotesDb.revision,
        builder: (context, _, _) {
          return FutureBuilder<List<Note>>(
            future: NotesDb.notes(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final notes = snapshot.data!;
              if (notes.isEmpty) return const _NoNotes();

              return ListView.separated(
                // Room for the FAB, and for the overlay's draggable launcher.
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                itemCount: notes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _NoteCard(note: notes[i]),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New note'),
      ),
    );
  }

  /// Pushes the editor.
  ///
  /// No devtray call here: DevtrayNavObserver sees the push, and the pop, and
  /// sets the `screen` field for both. The one thing worth doing is naming the
  /// route — an unnamed push reports `<unnamed MaterialPageRoute>`, which is
  /// honest but not useful.
  static Future<void> _openEditor(BuildContext context, Note? note) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'note_editor'),
        builder: (_) => NoteEditorScreen(note: note),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  const _NoteCard({required this.note});

  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await NotesDb.deleteRow(note.id);

    // Undo instead of a confirm dialog: deleting a note is cheap to reverse, and
    // a dialog on every swipe is the tax you pay for a mistake that rarely
    // happens. The restore puts the row back with its original id, so the
    // Storage page shows the same key returning.
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted "${note.title}"'),
        action: SnackBarAction(label: 'Undo', onPressed: () => NotesDb.restore(note)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) => _delete(context),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => NotesScreen._openEditor(context, note),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        note.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: note.pinned ? 'Unpin' : 'Pin',
                  onPressed: () => NotesDb.setPinned(note.id, !note.pinned),
                  icon: Icon(
                    note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 18,
                    color: note.pinned ? scheme.primary : scheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoNotes extends StatelessWidget {
  const _NoNotes();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.note_outlined, size: 40, color: scheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 10),
          Text('No notes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          const SizedBox(height: 4),
          Text(
            'Tap New note to write one.',
            style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
