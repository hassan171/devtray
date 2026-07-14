import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';

/// Edits a `List<String>` as chips — tap one to rename it, ✕ to remove it, `+`
/// to add.
///
/// Replaces the raw-JSON text field this used to be. Editing `["flutter",
/// "dart"]` by hand on a phone is exactly the authoring-from-scratch problem
/// worth avoiding, and it made "Invalid JSON" a failure mode you could hit by
/// mistyping a bracket. With chips each element is manipulated directly, so a
/// malformed list is unrepresentable.
///
/// Like a bool's switch, the chips *are* the editor — every change writes
/// straight through, so there's no Edit/Save step.
class StorageListEditor extends StatefulWidget {
  final List<String> values;
  final bool canEdit;
  final ValueChanged<List<String>> onChanged;

  const StorageListEditor({
    super.key,
    required this.values,
    required this.canEdit,
    required this.onChanged,
  });

  @override
  State<StorageListEditor> createState() => _StorageListEditorState();
}

class _StorageListEditorState extends State<StorageListEditor> {
  /// Index being renamed, or null. -1 means "adding a new one".
  int? _editingIndex;

  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit(int index) {
    setState(() {
      _editingIndex = index;
      _controller.text = index == -1 ? '' : widget.values[index];
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
    _focus.requestFocus();
  }

  void _commit() {
    final index = _editingIndex;
    if (index == null) return;

    final text = _controller.text.trim();
    final next = [...widget.values];

    if (text.isEmpty) {
      // Emptying an existing chip removes it; an empty new chip is just a
      // cancelled add.
      if (index >= 0) next.removeAt(index);
    } else if (index == -1) {
      next.add(text);
    } else {
      next[index] = text;
    }

    setState(() => _editingIndex = null);
    if (!_listEquals(next, widget.values)) widget.onChanged(next);
  }

  void _cancel() => setState(() => _editingIndex = null);

  void _remove(int index) {
    final next = [...widget.values]..removeAt(index);
    widget.onChanged(next);
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < widget.values.length; i++)
            if (_editingIndex == i)
              _ChipField(
                controller: _controller,
                focusNode: _focus,
                theme: t,
                onSubmit: _commit,
                onCancel: _cancel,
              )
            else
              _ValueChip(
                label: widget.values[i],
                theme: t,
                canEdit: widget.canEdit,
                onTap: () => _startEdit(i),
                onRemove: () => _remove(i),
              ),

          if (_editingIndex == -1)
            _ChipField(
              controller: _controller,
              focusNode: _focus,
              theme: t,
              onSubmit: _commit,
              onCancel: _cancel,
            )
          else if (widget.canEdit)
            _AddChip(theme: t, onTap: () => _startEdit(-1)),

          if (widget.values.isEmpty && _editingIndex == null && !widget.canEdit)
            Text('<empty>', style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: t.textMuted)),
        ],
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  final String label;
  final DebugOverlayTheme theme;
  final bool canEdit;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ValueChip({
    required this.label,
    required this.theme,
    required this.canEdit,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: canEdit ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.only(left: 8, right: canEdit ? 2 : 8, top: 3, bottom: 3),
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border.all(color: theme.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: theme.text),
            ),
            if (canEdit)
              IconButton(
                tooltip: 'Remove',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                icon: Icon(Icons.close, size: 12, color: theme.textMuted),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  final DebugOverlayTheme theme;
  final VoidCallback onTap;

  const _AddChip({required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: theme.accent),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 12, color: theme.accent),
            const SizedBox(width: 2),
            Text('Add', style: TextStyle(fontSize: 11, color: theme.accent)),
          ],
        ),
      ),
    );
  }
}

/// The inline field a chip becomes while it's being renamed or added.
class _ChipField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final DebugOverlayTheme theme;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  const _ChipField({
    required this.controller,
    required this.focusNode,
    required this.theme,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 60, maxWidth: 220),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: theme.text),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'value',
            hintStyle: TextStyle(fontSize: 11, color: theme.textMuted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.accent)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.accent)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.accent)),
            suffixIcon: IconButton(
              tooltip: 'Cancel',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              icon: Icon(Icons.close, size: 12, color: theme.textMuted),
              onPressed: onCancel,
            ),
            suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          onSubmitted: (_) => onSubmit(),
          // Committing on focus-loss means tapping elsewhere saves rather than
          // silently discarding what you typed.
          onTapOutside: (_) => onSubmit(),
        ),
      ),
    );
  }
}
