import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';
import 'storage_list_editor.dart';

/// One key/value row. Renders the right control for the value's **existing**
/// type, and writes back that same type.
///
/// Type preservation is the whole safety story. A store like SharedPreferences
/// has a setter per type and throws on the next *read* if you write the wrong
/// one — so an editor that turned every value into a String would be a landmine.
///
/// - `bool` → a switch
/// - `List` → chips ([StorageListEditor]), each one editable/removable
/// - `int` / `double` → a number field, rejected if it won't parse
/// - `String` → a text field
///
/// Bools and lists write straight through; the scalars use an Edit/Save step.
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

  // Lists never reach here — StorageListEditor owns them.
  static String _asText(Object? v) => switch (v) {
        null => '',
        final String s => s,
        _ => v.toString(),
      };

  static String _typeLabel(Object? v) => switch (v) {
        null => 'null',
        bool() => 'bool',
        int() => 'int',
        double() => 'double',
        String() => 'String',
        List() => 'List<String>',
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
                child: Text(
                  widget.storageKey,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: t.text),
                ),
              ),
              Text(_typeLabel(widget.value), style: TextStyle(fontSize: 10, color: t.textMuted)),
              if (widget.canEdit) ...[
                const SizedBox(width: 4),
                if (needsEditButton)
                  IconButton(
                    tooltip: _editing ? 'Save' : 'Edit',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: Icon(_editing ? Icons.check : Icons.edit, size: 14, color: _editing ? t.success : t.textMuted),
                    onPressed: () => _editing ? _save() : setState(() => _editing = true),
                  ),
                IconButton(
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(Icons.delete_outline, size: 14, color: t.error),
                  onPressed: widget.onDelete,
                ),
              ],
            ],
          ),
          if (isBool)
            Row(
              children: [
                Switch(
                  value: widget.value! as bool,
                  onChanged: widget.canEdit ? (v) => widget.onWrite(v) : null,
                  activeThumbColor: t.accent,
                ),
                Text(
                  '${widget.value}',
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: t.text),
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
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: t.text),
              decoration: InputDecoration(
                isDense: true,
                errorText: _error,
                contentPadding: const EdgeInsets.all(8),
                border: OutlineInputBorder(borderSide: BorderSide(color: t.border)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: t.border)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: t.accent)),
              ),
              onSubmitted: (_) => _save(),
            )
          else
            SelectableText(
              _asText(widget.value).isEmpty ? '<empty>' : _asText(widget.value),
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: t.text),
            ),
        ],
      ),
    );
  }
}
