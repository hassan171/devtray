import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../app_services.dart' show dio;
import '../users_box.dart';

/// Users from the Hive box, refilled from the network on pull-to-refresh.
///
/// The network traffic here is **incidental** — you pull to refresh because you
/// want fresh users, and a request happens. That's the difference between this
/// and a button marked "GET via dio": the overlay's Network page fills up as a
/// side effect of using the app, which is how it fills up in a real one.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Fetch on first open only if the box is empty, so a restart doesn't
    // re-hammer the API — and so there's something to see immediately.
    if (usersBox.isEmpty) _refresh();
  }

  Future<void> _refresh({int count = 100}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await fetchAndStoreUsers(dio, count: count);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      // Caught and shown, not swallowed — the overlay's Network page has the
      // failed request either way, and the app still has to say something.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ValueListenableBuilder<Box<User>>(
          valueListenable: usersBox.listenable(),
          builder: (context, box, _) {
            final users = box.values.toList()..sort((a, b) => a.id.compareTo(b.id));

            if (_error != null && users.isEmpty) {
              return _Message(
                icon: Icons.cloud_off,
                title: 'Could not load users',
                // The real reason, not "something went wrong" — this is a
                // developer-facing example, and the Network page has the rest.
                detail: _error!,
                action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
              );
            }

            if (users.isEmpty) {
              return _Message(
                icon: Icons.people_outline,
                title: _loading ? 'Fetching users…' : 'No users yet',
                detail: _loading ? 'From jsonplaceholder.typicode.com' : 'Pull down to fetch them.',
              );
            }

            return Column(
              children: [
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: ListView.separated(
                    // Always scrollable, so pull-to-refresh works even when the
                    // list is short.
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    itemCount: users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) => _UserCard(user: users[i]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        // 1000 users is the interesting one: it's what makes the Storage page's
        // list virtualisation and the Hive box size worth looking at.
        onPressed: _loading ? null : () => _refresh(count: 1000),
        icon: const Icon(Icons.download),
        label: const Text('Fetch 1000'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _UserCard extends StatelessWidget {
  final User user;
  const _UserCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
              child: Text(
                user.name.isEmpty ? '?' : user.name.characters.first.toUpperCase(),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username} · ${user.city}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  const _Message({required this.icon, required this.title, required this.detail, this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // A ListView, not a Center: RefreshIndicator needs a scrollable to hang off,
    // so an empty state that isn't scrollable can't be pulled.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
        Icon(icon, size: 40, color: scheme.onSurface.withValues(alpha: 0.3)),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 16),
          Center(child: action!),
        ],
      ],
    );
  }
}
