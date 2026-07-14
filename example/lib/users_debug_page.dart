import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'components/user_tile.dart';
import 'users_box.dart';

/// A custom page — this is what `DebugPage` is for.
///
/// The Storage page can already *browse* the Hive box, but only as key/value
/// text. When you know what the data is, a purpose-built view beats a generic
/// one: here the users render as cards, and the list updates live as the box
/// changes (fetch some, delete one, watch it react).
class UsersDebugPage extends DebugPage {
  const UsersDebugPage();

  @override
  String get title => 'Users';

  @override
  IconData? get icon => Icons.people_outline;

  @override
  Widget build(BuildContext context) => const _UsersView();
}

class _UsersView extends StatelessWidget {
  const _UsersView();

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);

    // Hive's own listenable — no manual refresh needed.
    return ValueListenableBuilder<Box<User>>(
      valueListenable: usersBox.listenable(),
      builder: (context, box, _) {
        final users = box.values.toList()..sort((a, b) => a.id.compareTo(b.id));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${users.length} cached in Hive',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.text),
                    ),
                  ),
                  if (users.isNotEmpty)
                    TextButton(
                      onPressed: box.clear,
                      child: Text('Clear box', style: TextStyle(fontSize: 12, color: t.error)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: users.isEmpty
                  ? Center(
                      child: Text(
                        'Empty — hit "Fetch users into Hive" on the home screen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.textMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: users.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
                      itemBuilder: (context, i) => UserTile(user: users[i], theme: t),
                    ),
            ),
          ],
        );
      },
    );
  }
}
