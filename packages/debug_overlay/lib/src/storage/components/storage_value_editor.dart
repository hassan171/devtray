import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';
import '../../core/debug_text_styles.dart';
import 'storage_list_editor.dart';

/// The colour a value's type is spoken in.
///
/// Type isn't trivia on this page — it's the safety story. A store like
/// SharedPreferences has a setter per type and throws on the next *read* if the
/// wrong one was written, so "what type is this?" is the question the row has to
/// answer before you touch it. Colour makes each type recognisable at a glance
/// rather than something you read.
Color storageTypeColor(Object? v, DebugOverlayTheme t) => switch (v) {
      null => t.textMuted,
      bool() => t.warning,
      int() || double() => t.accent,
      String() => t.success,
      List() || Map() => t.textMuted,
      _ => t.textMuted,
    };

/// Everything about a key/value pair that a search should look at — the key,
/// and the value as it's *rendered on screen*.
///
/// Matching the rendering matters. A `List<String>` shows as chips and a `Map`
/// as pretty-printed JSON, so searching `flutter` has to find the tag inside the
/// list, and `admin` the role inside the object. Matching `toString()` instead
/// would find `[flutter, dart]` but miss the JSON's quoting and indentation —
/// i.e. it would disagree with what you can see, which is the one thing a search
/// mustn't do.
///
/// Lowercased once by the caller, not here: this runs per key per keystroke.
String storageSearchableText(String key, Object? value) => '$key ${storageValueAsText(value)}';

/// A value as text, for search and for the scalar editor.
///
/// Lists are included even though [StorageListEditor] owns their *display* —
/// they're still readable on screen as chips, so they must be searchable.
String storageValueAsText(Object? v) => switch (v) {
      null => '',
      final String s => s,
      // A structured value (an object from a typed store) is shown as
      // pretty-printed JSON — its real shape, every field named.
      final Map<dynamic, dynamic> m => const JsonEncoder.withIndent('  ').convert(m),
      // Chips, one per element. Joined loosely: search shouldn't care about the
      // brackets and commas of `toString()`, which aren't on screen anyway.
      final List<dynamic> l => l.join(' '),
      _ => v.toString(),
    };

/// A pill naming the value's type — the control you get is chosen from it, and
/// it's what your edit will be written back as.
class StorageTypeBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StorageTypeBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label, style: DebugTextStyles.label(color: color, fontSize: 8)),
    );
  }
}

/// One key/value row. Renders the right control for the value's **existing**
/// type, and writes back that same type.
///
/// Type preservation is the whole safety story. A store like SharedPreferences
/// has a setter per type and throws on the next *read* if you write the wrong
/// one — so an editor that turned every value into a String would be a landmine.
///
/// - `bool` → a switch
/// - `List` → chips ([StorageListEditor]), each one editable/removable
/// - `Map` → pretty-printed JSON, parsed back to a `Map` (an object from a typed
///   store — the adapter rebuilds its model from it)
/// - `int` / `double` → a number field, rejected if it won't parse
/// - `String` → a text field
///
/// Bools and lists write straight through; everything else uses an Edit/Save step.
class StorageValueEditor extends StatefulWidget {
  final String storageKey;
  final Object? value;
  final bool canEdit;
  final ValueChanged<Object?> onWrite;
  final VoidCallback onDelete;

  const StorageValueEditor({
    super.key,
    required this.storageKey,
    required this.value,
    required this.canEdit,
    required this.onWrite,
    required this.onDelete,
  });

  @override
  State<StorageValueEditor> createState() => _StorageValueEditorState();
}

class _StorageValueEditorState extends State<StorageValueEditor> {
  bool _editing = false;
  late TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _asText(widget.value));
  }

  @override
  void didUpdateWidget(StorageValueEditor old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_editing) {
      _controller.text = _asText(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Shared with the page's search, so what you can read and what you can find
  // are the same string. (Lists never reach the scalar editor — StorageListEditor
  // owns them — but they're searchable, hence the shared function handling them.)
  static String _asText(Object? v) => storageValueAsText(v);

  static String _typeLabel(Object? v) => switch (v) {
        null => 'null',
        bool() => 'bool',
        int() => 'int',
        double() => 'double',
        String() => 'String',
        List() => 'List<String>',
        Map() => 'object',
        _ => v.runtimeType.toString(),
      };

  /// Parses the edited text back into the **original** type, or returns an error.
  ({Object? value, String? error}) _parse(String text) {
    final original = widget.value;

    switch (original) {
      case int():
        final v = int.tryParse(text.trim());
        return v == null ? (value: null, error: 'Not an int') : (value: v, error: null);

      case double():
        final v = double.tryParse(text.trim());
        return v == null ? (value: null, error: 'Not a number') : (value: v, error: null);

      // A structured value must go back as a Map, not the String the editor was
      // holding — otherwise a typed store would silently take a String where it
      // expects an object, and only fail later when something reads it.
      case Map():
        try {
          final decoded = jsonDecode(text);
          if (decoded is! Map) return (value: null, error: 'Not a JSON object');
          return (value: decoded, error: null);
        } catch (_) {
          return (value: null, error: 'Invalid JSON');
        }

      // Strings (and anything unrecognised) go back as-is. Lists never get here —
      // StorageListEditor owns them, so a malformed list is unrepresentable.
      default:
        return (value: text, error: null);
    }
  }

  void _save() {
    final parsed = _parse(_controller.text);
    if (parsed.error != null) {
      setState(() => _error = parsed.error);
      return;
    }
    setState(() {
      _error = null;
      _editing = false;
    });
    widget.onWrite(parsed.value);
  }

  /// Deleting a key is irreversible — there's no undo, and the store is the
  /// app's real state, not a scratch buffer. An edit is recoverable (you retype
  /// it); a delete of a key you didn't recognise isn't. So it asks first.
  Future<void> _confirmDelete() async {
    final t = DebugOverlayTheme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => DebugOverlayThemeScope(
        // Pushed on the app's Navigator, outside the overlay's subtree — the
        // theme has to be carried across.
        theme: t,
        child: AlertDialog(
          backgroundColor: t.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: t.border),
          ),
          title: Text('Delete key?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name the key: on a long store you may be several rows from where
              // you thought you were.
              Text(widget.storageKey, style: DebugTextStyles.debugMono(color: t.text, fontSize: 12)),
              const SizedBox(height: 8),
              Text(
                'This removes it from the store. There is no undo.',
                style: TextStyle(fontSize: 11, color: t.textMuted, height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Cancel', style: TextStyle(fontSize: 12, color: t.textMuted)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              // Danger colour, from the overlay's theme — a bare FilledButton
              // would take the host app's primary colour and read as benign.
              style: FilledButton.styleFrom(
                backgroundColor: t.error,
                foregroundColor: t.background,
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: Text('Delete', style: DebugTextStyles.label(color: t.background, fontSize: 10)),
            ),
          ],
        ),
      ),
    );

    if (confirmed ?? false) widget.onDelete();
  }

  static OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: c, width: w),
      );

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final isBool = widget.value is bool;
    final isList = widget.value is List;

    // Bools and lists are edited in place — the switch and the chips ARE the
    // editor, so neither needs the Edit/Save step a scalar does.
    final needsEditButton = !isBool && !isList;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                // A key is an identifier — data, not prose.
                child: Text(
                  widget.storageKey,
                  overflow: TextOverflow.ellipsis,
                  style: DebugTextStyles.debugMono(color: t.text, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 6),
              StorageTypeBadge(label: _typeLabel(widget.value), color: storageTypeColor(widget.value, t)),
              if (widget.canEdit) ...[
                const SizedBox(width: 2),
                if (needsEditButton)
                  IconButton(
                    tooltip: _editing ? 'Save' : 'Edit',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    icon: Icon(_editing ? Icons.check : Icons.edit_outlined, size: 14, color: _editing ? t.success : t.textMuted),
                    onPressed: () => _editing ? _save() : setState(() => _editing = true),
                  ),
                IconButton(
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                  icon: Icon(Icons.delete_outline, size: 14, color: t.error),
                  onPressed: _confirmDelete,
                ),
              ],
            ],
          ),
          if (isBool)
            Row(
              children: [
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: widget.value! as bool,
                    onChanged: widget.canEdit ? (v) => widget.onWrite(v) : null,
                    activeThumbColor: t.accent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.value}',
                  style: DebugTextStyles.debugMono(
                    // The literal the store holds — green when true, muted when
                    // false, so a screenful of flags reads at a glance.
                    color: widget.value == true ? t.success : t.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else if (isList)
            // Chips, not raw JSON. Each element is manipulated directly, so a
            // malformed list is unrepresentable — no "Invalid JSON" to hit by
            // mistyping a bracket.
            StorageListEditor(
              values: (widget.value! as List).map((e) => e.toString()).toList(),
              canEdit: widget.canEdit,
              onChanged: widget.onWrite,
            )
          else if (_editing)
            TextField(
              controller: _controller,
              autofocus: true,
              // A structured value is pretty-printed JSON — give it room.
              maxLines: widget.value is Map ? 10 : 1,
              cursorColor: t.accent,
              cursorWidth: 1.5,
              // You type JSON in here. The bare `monospace` alias only resolves
              // on Android/Linux and fell back to a proportional font elsewhere,
              // wrecking the indentation of what you were editing.
              style: DebugTextStyles.debugMono(color: t.text, fontSize: 12, height: 1.45),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: t.surface,
                errorText: _error,
                errorStyle: TextStyle(fontSize: 10, color: t.error),
                contentPadding: const EdgeInsets.all(10),
                border: _border(t.border),
                enabledBorder: _border(t.border.withValues(alpha: 0.8)),
                focusedBorder: _border(t.accent, 1.5),
                errorBorder: _border(t.error),
                focusedErrorBorder: _border(t.error, 1.5),
              ),
              onSubmitted: (_) => _save(),
            )
          else
            Builder(
              builder: (context) {
                final text = _asText(widget.value);
                final isEmpty = text.isEmpty;
                return SelectableText(
                  isEmpty ? 'empty' : text,
                  style: DebugTextStyles.debugMono(
                    color: isEmpty ? t.textMuted : t.text,
                    fontSize: 12,
                    height: 1.45,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
