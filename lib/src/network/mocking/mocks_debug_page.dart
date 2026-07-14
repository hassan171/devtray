import 'package:flutter/material.dart';

import '../../core/debug_overlay_theme.dart';
import '../../core/debug_page.dart';
import 'components/mock_rule_editor.dart';
import 'mock_rule.dart';
import 'mock_store.dart';

/// Intercept requests: force a response, inject latency, or simulate offline.
///
/// This is what turns the network inspector from an observer into a test
/// harness — it lets you reach app states (a 500, an empty list, a dead
/// backend) that otherwise need a server-side change.
class MocksDebugPage extends DebugPage {
  const MocksDebugPage();

  @override
  String get title => 'Mocks';

  @override
  IconData? get icon => Icons.alt_route;

  @override
  Widget build(BuildContext context) => const _MocksView();
}

class _MocksView extends StatelessWidget {
  const _MocksView();

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final store = MockStore.instance;

    return ValueListenableBuilder<List<MockRule>>(
      valueListenable: store.rules,
      builder: (context, rules, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const MockInterceptionBanner(),
            _MasterSwitches(theme: t),
            Divider(color: t.border),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Rules (${rules.length})',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: t.text),
                  ),
                ),
                if (rules.isNotEmpty)
                  TextButton(
                    onPressed: store.clear,
                    child: Text('Clear all', style: TextStyle(fontSize: 12, color: t.error)),
                  ),
                TextButton.icon(
                  icon: Icon(Icons.add, size: 16, color: t.accent),
                  label: Text('Add', style: TextStyle(fontSize: 12, color: t.accent)),
                  onPressed: () => MockRuleEditor.show(context),
                ),
              ],
            ),
            Expanded(
              child: rules.isEmpty
                  ? _EmptyState(theme: t)
                  : ListView.builder(
                      itemCount: rules.length,
                      itemBuilder: (context, i) => _RuleRow(rule: rules[i], theme: t),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Shown whenever anything is intercepting traffic.
///
/// A faked response that looks identical to a real one will cost you an
/// afternoon. This banner (and the badge on mocked rows) is the guard against
/// debugging a response you faked yourself and forgot about.
class MockInterceptionBanner extends StatelessWidget {
  const MockInterceptionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final store = MockStore.instance;

    // Rebuild on any of the three things that can turn interception on.
    return ListenableBuilder(
      listenable: Listenable.merge([store.offline, store.rulesEnabled, store.rules]),
      builder: (context, _) {
        if (!store.isIntercepting) return const SizedBox.shrink();

        final active = store.rules.value.where((r) => r.enabled).length;
        final message = store.offline.value
            ? 'Offline mode is ON — every request is being failed.'
            : '$active mock rule${active == 1 ? '' : 's'} active — some responses are faked.';

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: t.warning.withValues(alpha: 0.15),
            border: Border.all(color: t.warning),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber, size: 16, color: t.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.text)),
              ),
              TextButton(
                onPressed: () {
                  store.offline.value = false;
                  store.rulesEnabled.value = false;
                },
                child: Text('Turn off', style: TextStyle(fontSize: 11, color: t.warning)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MasterSwitches extends StatelessWidget {
  final DebugOverlayTheme theme;
  const _MasterSwitches({required this.theme});

  @override
  Widget build(BuildContext context) {
    final store = MockStore.instance;

    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: store.offline,
          builder: (context, offline, _) => SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: offline,
            onChanged: (v) => store.offline.value = v,
            activeThumbColor: theme.warning,
            title: Text('Simulate offline', style: TextStyle(fontSize: 13, color: theme.text)),
            subtitle: Text(
              'Fail every request, as if the network were unreachable. Overrides all rules.',
              style: TextStyle(fontSize: 11, color: theme.textMuted),
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: store.rulesEnabled,
          builder: (context, enabled, _) => SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: enabled,
            onChanged: (v) => store.rulesEnabled.value = v,
            activeThumbColor: theme.accent,
            title: Text('Apply rules', style: TextStyle(fontSize: 13, color: theme.text)),
            subtitle: Text(
              'Park every rule at once without deleting them.',
              style: TextStyle(fontSize: 11, color: theme.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  final MockRule rule;
  final DebugOverlayTheme theme;

  const _RuleRow({required this.rule, required this.theme});

  @override
  Widget build(BuildContext context) {
    final store = MockStore.instance;
    final color = switch (rule.action) {
      MockAction.respond => rule.statusCode >= 400 ? theme.error : theme.success,
      MockAction.fail => theme.error,
      MockAction.delayOnly => theme.warning,
    };

    return Opacity(
      opacity: rule.enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.border, width: 0.5)),
        ),
        child: Row(
          children: [
            Switch(
              value: rule.enabled,
              onChanged: (_) => store.toggle(rule.id),
              activeThumbColor: theme.accent,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (rule.method != null) ...[
                        Text(
                          rule.method!,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.textMuted),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          rule.urlPattern,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: theme.text),
                        ),
                      ),
                      if (rule.isRegex) ...[
                        const SizedBox(width: 6),
                        Text('regex', style: TextStyle(fontSize: 9, color: theme.accent)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(rule.summary, style: TextStyle(fontSize: 11, color: color)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit',
              icon: Icon(Icons.edit, size: 16, color: theme.textMuted),
              onPressed: () => MockRuleEditor.show(context, existing: rule),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline, size: 16, color: theme.error),
              onPressed: () => store.remove(rule.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final DebugOverlayTheme theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alt_route, size: 32, color: theme.textMuted),
            const SizedBox(height: 8),
            Text('No mock rules', style: TextStyle(color: theme.textMuted)),
            const SizedBox(height: 4),
            Text(
              'Tip: open a request on the Network page and use "Mock this" — '
              'the rule is prefilled with its real response, so you edit rather '
              'than write JSON from scratch.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: theme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
