import 'package:flutter/material.dart';

import '../../core/devtray_theme.dart';
import '../../core/debug_text_styles.dart';
import 'components/mock_rule_editor.dart';
import 'mock_rule.dart';
import 'devtray_mocks.dart';

/// The mocking UI — intercept requests: force a response, inject latency, or
/// simulate offline.
///
/// This is what turns the network inspector from an observer into a test
/// harness — it lets you reach app states (a 500, an empty list, a dead
/// backend) that otherwise need a server-side change.
///
/// Not a page of its own — it's shown *inside* the Network tab, reached via its
/// "Mocks" button (see [NetworkDebugPage]). Kept as a standalone widget so that
/// embedding is a plain child, and so a host could still drop it anywhere.
class MocksView extends StatelessWidget {
  const MocksView({super.key});

  @override
  Widget build(BuildContext context) {
    final t = DevtrayTheme.of(context);
    final store = DevtrayMocks.instance;

    return ValueListenableBuilder<List<MockRule>>(
      valueListenable: store.rules,
      builder: (context, rules, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No interception banner here on purpose. You're standing on the
            // page that owns the switches — the armed tint on them already says
            // what the banner would, and inserting a block above them shoved
            // the whole list down every time you toggled one. The warning that
            // matters is on the Network page, where the faking isn't visible.
            _MasterSwitches(theme: t),
            Divider(color: t.border),
            Row(
              children: [
                Text('Rules', style: DebugTextStyles.label(color: t.textMuted, fontSize: 11)),
                const SizedBox(width: 6),
                Text(
                  '${rules.length}',
                  style: DebugTextStyles.debugMono(color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (rules.isNotEmpty)
                  TextButton(
                    onPressed: store.clear,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('Clear all', style: TextStyle(fontSize: 12, color: t.error)),
                  ),
                const SizedBox(width: 4),
                // Adding a rule is the primary action here, so it's the only
                // filled control on the screen.
                Material(
                  color: t.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => MockRuleEditor.show(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 14, color: t.accent),
                          const SizedBox(width: 4),
                          // "New rule", not "Add rule" — the editor's own submit
                          // button is "Add rule", and two controls with the same
                          // label doing different things is a trap.
                          Text('New rule', style: DebugTextStyles.label(color: t.accent, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
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
    final t = DevtrayTheme.of(context);
    final store = DevtrayMocks.instance;

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
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.warning.withValues(alpha: 0.12),
            border: Border.all(color: t.warning.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // A solid warning spine. This banner is the only thing standing
                // between you and an afternoon spent debugging a response you
                // faked yourself — it should read as a live alarm, not a hint.
                Container(width: 3, color: t.warning),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Icon(Icons.warning_amber_rounded, size: 16, color: t.warning),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      message,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: t.text, height: 1.35),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // The escape hatch. Filled rather than a bare TextButton — when
                // the banner is up, turning it off is the one thing you're most
                // likely to want.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Material(
                    color: t.warning.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        store.offline.value = false;
                        store.rulesEnabled.value = false;
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Text('Turn off', style: DebugTextStyles.label(color: t.warning, fontSize: 10)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One master switch: title, explanation, and a compact toggle.
///
/// Hand-built rather than a [SwitchListTile] so the toggle can be scaled down
/// and the row can carry an "armed" tint when it's on — a stock tile gives no
/// way to say "this one is currently changing your app's behaviour".
class _MasterSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;
  final DevtrayTheme theme;

  const _MasterSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.activeColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // The whole row toggles — a 20px switch is a poor target on its own.
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            // Tinted only while armed, so an active override is visible without
            // reading the switch position.
            color: value ? activeColor.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: value ? activeColor : theme.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(subtitle, style: TextStyle(fontSize: 10, color: theme.textMuted, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: activeColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasterSwitches extends StatelessWidget {
  final DevtrayTheme theme;
  const _MasterSwitches({required this.theme});

  @override
  Widget build(BuildContext context) {
    final store = DevtrayMocks.instance;

    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: store.offline,
          builder: (context, offline, _) => _MasterSwitch(
            theme: theme,
            value: offline,
            onChanged: (v) => store.offline.value = v,
            // Warning, not accent: this one fails every request in the app.
            activeColor: theme.warning,
            title: 'Simulate offline',
            subtitle: 'Fail every request, as if the network were unreachable. Overrides all rules.',
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: store.rulesEnabled,
          builder: (context, enabled, _) => _MasterSwitch(
            theme: theme,
            value: enabled,
            onChanged: (v) => store.rulesEnabled.value = v,
            activeColor: theme.accent,
            title: 'Apply rules',
            subtitle: 'Park every rule at once without deleting them.',
          ),
        ),
      ],
    );
  }
}

/// A small square marker, e.g. the `regex` flag on a rule.
class _MiniTag extends StatelessWidget {
  final String text;
  final Color color;
  const _MiniTag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text, style: DebugTextStyles.label(color: color, fontSize: 8)),
    );
  }
}

/// One rule in the list.
///
/// Mirrors the request row's language on purpose — a spine carrying the action's
/// colour, mono for the pattern (it's matched against URLs, so it *is* data),
/// and the outcome summary in that same colour. A rule that forces a 500 should
/// look as alarming as the 500 it produces.
class _RuleRow extends StatelessWidget {
  final MockRule rule;
  final DevtrayTheme theme;

  const _RuleRow({required this.rule, required this.theme});

  @override
  Widget build(BuildContext context) {
    final store = DevtrayMocks.instance;
    final color = switch (rule.action) {
      MockAction.respond => rule.statusCode >= 400 ? theme.error : theme.success,
      MockAction.fail => theme.error,
      MockAction.delayOnly => theme.warning,
    };

    // A disabled rule is inert, so it recedes — but only the *description*
    // fades. Blanket-dimming the row would dim the switch and the delete button
    // too, making live controls look inert and un-tappable.
    final contentOpacity = rule.enabled ? 1.0 : 0.5;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.border.withValues(alpha: 0.6), width: 0.5)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Only an *enabled* rule is doing anything, so only an enabled rule
            // gets a live spine.
            Container(width: 2, color: rule.enabled ? color : theme.border),
            const SizedBox(width: 8),
            // Compact: a full-size Switch is ~60px and would outweigh the rule
            // it toggles.
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: rule.enabled,
                onChanged: (_) => store.toggle(rule.id),
                activeThumbColor: theme.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Opacity(
                opacity: contentOpacity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (rule.method != null) ...[
                          _MiniTag(text: rule.method!, color: theme.textMuted),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            rule.urlPattern,
                            overflow: TextOverflow.ellipsis,
                            style: DebugTextStyles.debugMono(color: theme.text, fontSize: 12, height: 1.3),
                          ),
                        ),
                        if (rule.isRegex) ...[
                          const SizedBox(width: 4),
                          _MiniTag(text: 'RE', color: theme.accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      rule.summary,
                      style: DebugTextStyles.debugMono(color: color, fontSize: 11, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Edit',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.edit_outlined, size: 15, color: theme.textMuted),
              onPressed: () => MockRuleEditor.show(context, existing: rule),
            ),
            IconButton(
              tooltip: 'Delete',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(Icons.delete_outline, size: 15, color: theme.error),
              onPressed: () => store.remove(rule.id),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final DevtrayTheme theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alt_route, size: 28, color: theme.textMuted.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              'No mock rules',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.text),
            ),
            const SizedBox(height: 4),
            Text(
              'Open a request on the Network page and hit "Mock this request" —\n'
              'the rule arrives prefilled with its real URL, status and body,\n'
              'so you edit rather than write JSON from scratch.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: theme.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
