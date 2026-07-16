import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/material.dart';

import '../notes_db.dart';

/// Write a note, or edit one.
///
/// Every save is a real SQLite write, so it shows up on the Storage page's
/// `notes` table — and every save also writes a log line, so the Logs page has
/// something that came from the app rather than from a button labelled "write a
/// log".
class NoteEditorScreen extends StatefulWidget {
  /// Null to create.
  final Note? note;

  const NoteEditorScreen({super.key, this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final _title = TextEditingController(text: widget.note?.title ?? '');
  late final _body = TextEditingController(text: widget.note?.body ?? '');

  bool get _isNew => widget.note == null;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A note needs a title.')),
      );
      return;
    }

    final navigator = Navigator.of(context);

    if (_isNew) {
      final id = await NotesDb.insert(title: title, body: _body.text.trim());
      // A real app logs real things. This lands on the Logs page with a tag and
      // a level, next to the framework's own noise — which is the point: the
      // overlay captures what the app already says, it doesn't need special
      // instrumentation.
      LogStore.instance.log('Created note $id: "$title"', tag: 'notes');
    } else {
      await NotesDb.upsert(widget.note!.id, {
        'title': title,
        'body': _body.text.trim(),
        'pinned': widget.note!.pinned ? 1 : 0,
      });
      LogStore.instance.log('Updated note ${widget.note!.id}', tag: 'notes');
    }

    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New note' : 'Edit note'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Save'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _title,
            autofocus: _isNew,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface),
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 6,
            maxLines: 14,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: 14, height: 1.45, color: scheme.onSurface),
            decoration: const InputDecoration(
              labelText: 'Body',
              alignLabelWithHint: true,
            ),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 16),
            // The id is the note's identity in SQLite — and the key you'd search
            // for on the Storage page. Worth surfacing in an example whose job is
            // to connect the two.
            Text(
              'Row id ${widget.note!.id} in the notes table — find it on the Storage page.',
              style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ],
      ),
    );
  }
}
