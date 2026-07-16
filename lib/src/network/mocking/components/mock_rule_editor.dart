import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/debug_overlay_theme.dart';
import '../../../core/debug_text_styles.dart';
import '../../network_log_store.dart';
import '../mock_rule.dart';
import '../mock_store.dart';

/// Add/edit a mock rule.
///
/// The important entry point is [showForEntry]: it seeds the form from a real
/// captured request — URL, method, status and the **actual response body** — so
/// you edit rather than author from scratch. That's the common case (take a 200
/// and make it a 500; take a list and make it empty), and authoring JSON by hand
/// on a phone is miserable.
class MockRuleEditor extends StatefulWidget {
  final MockRule? existing;
  final MockRule? seed;

  const MockRuleEditor({super.key, this.existing, this.seed});

  static Future<void> show(BuildContext context, {MockRule? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => DebugOverlayThemeScope(
        theme: DebugOverlayTheme.of(context),
        child: MockRuleEditor(existing: existing),
      ),
    );
  }

  /// Seeds a new rule from a captured request, prefilling its real response.
  static Future<void> showForEntry(BuildContext context, NetworkLogEntry entry) {
    final body = entry.responseBody;
    final seed = MockRule(
      id: MockStore.instance.nextId(),
      // Path only, not the full URL — a rule keyed to the host would break the
      // moment you point the app at a different environment.
      urlPattern: entry.uri.path,
      method: entry.method,
      statusCode: entry.statusCode ?? 200,
      body: body == null ? null : (body is String ? body : const JsonEncoder.withIndent('  ').convert(body)),
    );

    return showDialog<void>(
      context: context,
      builder: (_) => DebugOverlayThemeScope(
        theme: DebugOverlayTheme.of(context),
        child: MockRuleEditor(seed: seed),
      ),
    );
  }

  @override
  State<MockRuleEditor> createState() => _MockRuleEditorState();
}

class _MockRuleEditorState extends State<MockRuleEditor> {
  late final MockRule _base = widget.existing ?? widget.seed ?? MockRule(id: MockStore.instance.nextId(), urlPattern: '');

  late final _urlController = TextEditingController(text: _base.urlPattern);
  late final _bodyController = TextEditingController(text: _base.body ?? '');
  late final _statusController = TextEditingController(text: _base.statusCode.toString());
  late final _delayController = TextEditingController(text: (_base.delay?.inMilliseconds ?? 0).toString());

  late bool _isRegex = _base.isRegex;
  late String? _method = _base.method;
  late MockAction _action = _base.action;

  String? _bodyError;

  @override
  void dispose() {
    _urlController.dispose();
    _bodyController.dispose();
    _statusController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  bool _validate() {
    if (_action != MockAction.respond) return true;
    final text = _bodyController.text.trim();
    if (text.isEmpty) return true;

    // Only JSON is validated — a plain-text body is legitimate, so only complain
    // when it *looks* like JSON and isn't.
    if (!text.startsWith('{') && !text.startsWith('[')) return true;
    try {
      jsonDecode(text);
      setState(() => _bodyError = null);
      return true;
    } catch (e) {
      setState(() => _bodyError = 'Invalid JSON');
      return false;
    }
  }

  void _save() {
    if (!_validate()) return;

    final rule = _base.copyWith(
      urlPattern: _urlController.text.trim(),
      isRegex: _isRegex,
      method: () => _method,
      action: _action,
      delay: () {
        final ms = int.tryParse(_delayController.text) ?? 0;
        return ms <= 0 ? null : Duration(milliseconds: ms);
      },
      statusCode: int.tryParse(_statusController.text) ?? 200,
      body: () => _bodyController.text.isEmpty ? null : _bodyController.text,
      enabled: true,
    );

    final store = MockStore.instance;
    widget.existing == null ? store.add(rule) : store.update(rule);

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = DebugOverlayTheme.of(context);
    final isEdit = widget.existing != null;

    return Dialog(
      backgroundColor: t.background,
      clipBehavior: Clip.antiAlias,
      // The overlay draws its own chrome — a bare Dialog would inherit the host
      // app's shape and shadow and stop looking like part of the tools.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: t.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.alt_route, size: 15, color: t.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    // Cased as written, not `.toUpperCase()`d — rewriting the
                    // string changes the widget's real text, which breaks
                    // lookups and makes screen readers spell it out.
                    child: Text(isEdit ? 'Edit mock rule' : 'New mock rule', style: DebugTextStyles.label(color: t.text, fontSize: 12)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: Icon(Icons.close, size: 16, color: t.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Divider(color: t.border, height: 1),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Field(label: 'URL contains', hint: '/orders', controller: _urlController, theme: t),
                      const SizedBox(height: 12),
                      Row(
                        // Both sit on the same baseline. The picker is taller
                        // (its label sits above its box), so without this the
                        // toggle floated against the picker's top edge.
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            // Aligns the switch with the picker's *box*, not its
                            // label.
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _Toggle(label: 'Regex', value: _isRegex, onChanged: (v) => setState(() => _isRegex = v), theme: t),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _MethodPicker(value: _method, onChanged: (v) => setState(() => _method = v), theme: t),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _ActionPicker(value: _action, onChanged: (v) => setState(() => _action = v), theme: t),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_action == MockAction.respond) ...[
                            Expanded(
                              child: _Field(label: 'Status code', hint: '500', controller: _statusController, theme: t, numeric: true),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: _Field(label: 'Delay (ms)', hint: '0', controller: _delayController, theme: t, numeric: true),
                          ),
                        ],
                      ),
                      if (_action == MockAction.respond) ...[
                        const SizedBox(height: 12),
                        _Field(
                          label: 'Response body',
                          hint: '{"message": "boom"}',
                          controller: _bodyController,
                          theme: t,
                          maxLines: 8,
                          monospace: true,
                          errorText: _bodyError,
                        ),
                      ],
                      // What the chosen action actually does. These aren't
                      // decoration — "fail" vs "delay only" is the difference
                      // between the server being contacted or not.
                      if (_action == MockAction.fail)
                        _ActionNote(
                          theme: t,
                          color: t.error,
                          text: 'The request will fail as if the network were unreachable — a connection error, not an HTTP status.',
                        ),
                      if (_action == MockAction.delayOnly)
                        _ActionNote(
                          theme: t,
                          color: t.warning,
                          text: 'The request still reaches the real server — it just arrives late. Use it to surface loading states and races.',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: Text('Cancel', style: TextStyle(fontSize: 12, color: t.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  // Rebuild as the URL is typed — without listening to the
                  // controller the button would evaluate `isEmpty` once at build
                  // time and stay disabled forever.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _urlController,
                    builder: (context, value, _) {
                      final enabled = value.text.trim().isNotEmpty;
                      return FilledButton(
                        onPressed: enabled ? _save : null,
                        // Coloured from the overlay's own theme. A bare
                        // FilledButton takes the *host app's* primary colour,
                        // so the one button that commits the rule would clash
                        // with every other control in the tools.
                        style: FilledButton.styleFrom(
                          backgroundColor: t.accent,
                          foregroundColor: t.background,
                          disabledBackgroundColor: t.border,
                          disabledForegroundColor: t.textMuted,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: Text(isEdit ? 'Save' : 'Add rule', style: DebugTextStyles.label(color: enabled ? t.background : t.textMuted, fontSize: 10)),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final DebugOverlayTheme theme;
  final int maxLines;
  final bool numeric;
  final bool monospace;
  final String? errorText;

  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.theme,
    this.maxLines = 1,
    this.numeric = false,
    this.monospace = false,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: DebugTextStyles.label(color: theme.textMuted, fontSize: 10)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: numeric ? TextInputType.number : null,
            cursorColor: theme.accent,
            cursorWidth: 1.5,
            // A mono field here isn't decoration: you author JSON and URL
            // patterns in it. It was asking for the bare `monospace` alias,
            // which silently falls back to a proportional font off
            // Android/Linux — so hand-indented JSON came out ragged.
            style: monospace ? DebugTextStyles.debugMono(color: theme.text, fontSize: 12, height: 1.45) : TextStyle(fontSize: 13, color: theme.text),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: theme.textMuted, fontSize: 12),
              errorText: errorText,
              errorStyle: TextStyle(fontSize: 10, color: theme.error),
              isDense: true,
              filled: true,
              fillColor: theme.surface,
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.border.withValues(alpha: 0.8)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.accent, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: theme.error, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tinted note explaining what the selected action does.
///
/// Carries the action's own colour so the consequence is legible before you
/// read it — "fail" is destructive, "delay only" still hits the real server.
class _ActionNote extends StatelessWidget {
  final String text;
  final Color color;
  final DebugOverlayTheme theme;

  const _ActionNote({required this.text, required this.color, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 11, color: theme.text, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final DebugOverlayTheme theme;

  const _Toggle({required this.label, required this.value, required this.onChanged, required this.theme});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // The label toggles too — a scaled-down switch is a small target alone.
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 0.75,
              child: Switch(value: value, onChanged: onChanged, activeThumbColor: theme.accent, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: value ? theme.accent : theme.text, fontWeight: value ? FontWeight.w600 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final DebugOverlayTheme theme;

  static const _methods = [null, 'GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

  const _MethodPicker({required this.value, required this.onChanged, required this.theme});

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: c, width: w),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // An external label, like every other field here. A floating
        // `labelText` renders *above* the box, where it collided with the Regex
        // toggle sitting beside it.
        Text('Method', style: DebugTextStyles.label(color: theme.textMuted, fontSize: 10)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String?>(
          initialValue: value,
          isDense: true,
          dropdownColor: theme.background,
          // Matches _Field's frame, so the row of controls reads as one set.
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: theme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            border: border(theme.border),
            enabledBorder: border(theme.border.withValues(alpha: 0.8)),
            focusedBorder: border(theme.accent, 1.5),
          ),
          items: [
            for (final m in _methods)
              DropdownMenuItem(
                value: m,
                // A method is data — mono, like it is on every request row.
                child: Text(
                  m ?? 'Any',
                  style: m == null
                      ? TextStyle(fontSize: 12, color: theme.textMuted)
                      : DebugTextStyles.debugMono(color: theme.text, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ActionPicker extends StatelessWidget {
  final MockAction value;
  final ValueChanged<MockAction> onChanged;
  final DebugOverlayTheme theme;

  const _ActionPicker({required this.value, required this.onChanged, required this.theme});

  static String labelOf(MockAction a) => switch (a) {
    MockAction.respond => 'Fake response',
    MockAction.fail => 'Fail (offline)',
    MockAction.delayOnly => 'Delay only',
  };

  @override
  Widget build(BuildContext context) {
    // Each action's consequence, in colour: faking is neutral-accent, failing is
    // destructive, delaying still hits the real server.
    Color colorOf(MockAction a) => switch (a) {
      MockAction.respond => theme.accent,
      MockAction.fail => theme.error,
      MockAction.delayOnly => theme.warning,
    };
    final selectedColor = colorOf(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Action', style: DebugTextStyles.label(color: theme.textMuted, fontSize: 10)),
        const SizedBox(height: 4),
        SegmentedButton<MockAction>(
          segments: [
            for (final a in MockAction.values)
              ButtonSegment(
                value: a,
                label: Text(labelOf(a), style: const TextStyle(fontSize: 11)),
              ),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
          showSelectedIcon: false,
          // Fully themed from the overlay. Unstyled, this takes the *host app's*
          // Material theme — a dark overlay inside a light app would show a
          // light control here and nowhere else.
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? selectedColor.withValues(alpha: 0.18) : Colors.transparent,
            ),
            foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? selectedColor : theme.textMuted),
            side: WidgetStateProperty.all(BorderSide(color: theme.border)),
            textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          ),
        ),
      ],
    );
  }
}
