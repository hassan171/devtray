import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_services.dart' show todos;
import '../counter_cubit.dart';
import '../session_provider.dart';

/// Session (Riverpod) and a todo list (bloc), on one screen.
///
/// Two state libraries, side by side, in one app — which is the situation the
/// State page is actually built for. Nothing here chooses between them, and the
/// overlay shows both on a single page without being told which is which.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: const [
        _SessionCard(),
        SizedBox(height: 12),
        _TodosCard(),
      ],
    );
  }
}

/// The signed-in user, from a Riverpod `NotifierProvider`.
class _SessionCard extends ConsumerWidget {
  const _SessionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(sessionProvider);
    final signedIn = user != 'anonymous';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: signedIn ? scheme.primary.withValues(alpha: 0.15) : scheme.onSurface.withValues(alpha: 0.08),
                  child: Icon(
                    signedIn ? Icons.person : Icons.person_outline,
                    size: 20,
                    color: signedIn ? scheme.primary : scheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signedIn ? user : 'Not signed in',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
                      ),
                      Text(
                        'Riverpod · sessionProvider',
                        style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
                if (signedIn)
                  OutlinedButton(
                    onPressed: () => ref.read(sessionProvider.notifier).signOut(),
                    child: const Text('Sign out'),
                  )
                else
                  FilledButton(
                    onPressed: () => ref.read(sessionProvider.notifier).signIn('ada'),
                    child: const Text('Sign in'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A todo list, from a bloc.
class _TodosCard extends StatelessWidget {
  const _TodosCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Todos',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
                      ),
                      Text(
                        'bloc · TodoBloc',
                        style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Add a todo',
                  onPressed: () => todos.add(TodoAdded('todo ${DateTime.now().second}')),
                  icon: const Icon(Icons.add, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // StreamBuilder rather than flutter_bloc: the example already takes
            // `bloc` but not `flutter_bloc`, and one stream is not worth a
            // dependency. A real app would use BlocBuilder.
            StreamBuilder<List<String>>(
              stream: todos.stream,
              initialData: todos.state,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const [];
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nothing to do.',
                      style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.5)),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(Icons.check_box_outline_blank, size: 16, color: scheme.onSurface.withValues(alpha: 0.4)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(item, style: TextStyle(fontSize: 13, color: scheme.onSurface)),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => todos.add(const TodoCleared()),
                        child: const Text('Clear all'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
