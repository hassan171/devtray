import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';

import '../users_box.dart';

/// One user row. Tap it (or the pencil) to expand into a per-field editor.
///
/// Deliberately NOT a single text field holding
/// `Name (@username) · email · city` — that's the same "author the whole value
/// by hand" problem the Storage page's list chips replaced. Each field gets its
/// own input, so a malformed user is unrepresentable.
class UserTile extends StatefulWidget {
  final User user;
  final DevtrayTheme theme;

  const UserTile({super.key, required this.user, required this.theme});

  @override
  State<UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<UserTile> {
  bool _editing = false;

  late final _name = TextEditingController(text: widget.user.name);
  late final _username = TextEditingController(text: widget.user.username);
  late final _email = TextEditingController(text: widget.user.email);
  late final _city = TextEditingController(text: widget.user.city);

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _city.dispose();
    super.dispose();
  }

  void _resetControllers() {
    _name.text = widget.user.name;
    _username.text = widget.user.username;
    _email.text = widget.user.email;
    _city.text = widget.user.city;
  }

  Future<void> _save() async {
    final updated = widget.user.copyWith(
      name: _name.text.trim(),
      username: _username.text.trim(),
      email: _email.text.trim(),
      city: _city.text.trim(),
    );

    // Writes straight into the typed box — the ValueListenableBuilder on the
    // page rebuilds from it, so there's nothing to refresh by hand.
    await usersBox.put(widget.user.id.toString(), updated);
    if (mounted) setState(() => _editing = false);
  }

  void _cancel() {
    _resetControllers();
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: t.accent.withValues(alpha: 0.15),
                child: Text(
                  '${widget.user.id}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: t.accent),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _editing
                    ? Text(
                        'Editing user ${widget.user.id}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.accent),
                      )
                    : InkWell(
                        onTap: () => setState(() => _editing = true),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.user.name,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@${widget.user.username} · ${widget.user.email}',
                              style: TextStyle(fontSize: 11, color: t.textMuted),
                            ),
                            Text(widget.user.city, style: TextStyle(fontSize: 11, color: t.textMuted)),
                          ],
                        ),
                      ),
              ),
              if (_editing) ...[
                IconButton(
                  tooltip: 'Cancel',
                  icon: Icon(Icons.close, size: 16, color: t.textMuted),
                  onPressed: _cancel,
                ),
                IconButton(
                  tooltip: 'Save',
                  icon: Icon(Icons.check, size: 16, color: t.success),
                  onPressed: _save,
                ),
              ] else ...[
                IconButton(
                  tooltip: 'Edit',
                  icon: Icon(Icons.edit, size: 16, color: t.textMuted),
                  onPressed: () => setState(() => _editing = true),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(Icons.delete_outline, size: 16, color: t.error),
                  onPressed: () => usersBox.delete(widget.user.id.toString()),
                ),
              ],
            ],
          ),
          if (_editing)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 8),
              child: Column(
                children: [
                  _Field(label: 'Name', controller: _name, theme: t),
                  _Field(label: 'Username', controller: _username, theme: t),
                  _Field(label: 'Email', controller: _email, theme: t),
                  // Last field submits — a small thing, but it means you can
                  // edit a user without ever leaving the keyboard.
                  _Field(label: 'City', controller: _city, theme: t, onSubmitted: _save),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final DevtrayTheme theme;
  final VoidCallback? onSubmitted;

  const _Field({
    required this.label,
    required this.controller,
    required this.theme,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: TextStyle(fontSize: 11, color: theme.textMuted)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(fontSize: 12, color: theme.text),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(borderSide: BorderSide(color: theme.border)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: theme.border)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: theme.accent)),
              ),
              onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
            ),
          ),
        ],
      ),
    );
  }
}
