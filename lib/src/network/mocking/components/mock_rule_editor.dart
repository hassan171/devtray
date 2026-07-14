import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/debug_overlay_theme.dart';
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
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit mock rule' : 'New mock rule',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: t.text),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: t.text),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Field(
                        label: 'URL contains',
                        hint: '/orders',
                        controller: _urlController,
                        theme: t,
                      ),
                      Row(
                        children: [
                          _Toggle(
                            label: 'Regex',
                            value: _isRegex,
                            onChanged: (v) => setState(() => _isRegex = v),
                            theme: t,
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: _MethodPicker(value: _method, onChanged: (v) => setState(() => _method = v), theme: t)),
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
                      if (_action == MockAction.fail)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'The request will fail as if the network were unreachable — a connection error, not an HTTP status.',
                            style: TextStyle(fontSize: 11, color: t.textMuted),
                          ),
                        ),
                      if (_action == MockAction.delayOnly)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'The request still reaches the real server — it just arrives late. Use it to surface loading states and races.',
                            style: TextStyle(fontSize: 11, color: t.textMuted),
                          ),
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
                    child: Text('Cancel', style: TextStyle(color: t.textMuted)),
                  ),
                  const SizedBox(width: 8),
                  // Rebuild as the URL is typed — without listening to the
                  // controller the button would evaluate `isEmpty` once at build
                  // time and stay disabled forever.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _urlController,
                    builder: (context, value, _) => FilledButton(
                      onPressed: value.text.trim().isEmpty ? null : _save,
                      child: Text(isEdit ? 'Save' : 'Add rule'),
                    ),
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
          Text(label, style: TextStyle(fontSize: 11, color: theme.textMuted)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: numeric ? TextInputType.number : null,
            style: TextStyle(
              fontSize: 12,
              color: theme.text,
              fontFamily: monospace ? 'monospace' : null,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: theme.textMuted, fontSize: 12),
              errorText: errorText,
              isDense: true,
              contentPadding: const EdgeInsets.all(8),
              border: OutlineInputBorder(borderSide: BorderSide(color: theme.border)),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: theme.border)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: theme.accent)),
            ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(value: value, onChanged: onChanged, activeThumbColor: theme.accent),
        Text(label, style: TextStyle(fontSize: 12, color: theme.text)),
      ],
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
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isDense: true,
      dropdownColor: theme.background,
      decoration: InputDecoration(
        labelText: 'Method',
        labelStyle: TextStyle(fontSize: 11, color: theme.textMuted),
        isDense: true,
        contentPadding: const EdgeInsets.all(8),
        border: OutlineInputBorder(borderSide: BorderSide(color: theme.border)),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: theme.border)),
      ),
      items: [
        for (final m in _methods)
          DropdownMenuItem(
            value: m,
            child: Text(m ?? 'Any', style: TextStyle(fontSize: 12, color: theme.text)),
          ),
      ],
      onChanged: onChanged,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Action', style: TextStyle(fontSize: 11, color: theme.textMuted)),
        const SizedBox(height: 4),
        SegmentedButton<MockAction>(
          segments: [
            for (final a in MockAction.values)
              ButtonSegment(value: a, label: Text(labelOf(a), style: const TextStyle(fontSize: 11))),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
          showSelectedIcon: false,
        ),
      ],
    );
  }
}
