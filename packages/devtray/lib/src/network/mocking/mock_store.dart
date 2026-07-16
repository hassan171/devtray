import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'mock_rule.dart';

/// Where mock rules are saved between runs.
///
/// Rules are the one thing in this package worth persisting: you'd otherwise
/// re-add "force /orders to 500" after every hot restart, which is exactly when
/// you're iterating on an error state. It's a small JSON blob of rules — no
/// logs, no captured traffic — which is why this is the only thing written to
/// disk when nothing else is.
abstract class MockRuleStorage {
  Future<String?> read();
  Future<void> write(String json);
}

/// Default: keeps rules for the process lifetime only. Swap in
/// [SharedPreferencesMockRuleStorage] (or your own) to survive restarts.
class InMemoryMockRuleStorage implements MockRuleStorage {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String json) async => _value = json;
}

/// Holds the interception rules and the global offline switch, and is consulted
/// by the adapters on every request.
///
/// ```dart
/// // Simulate a dead backend:
/// MockStore.instance.offline.value = true;
///
/// // Force one endpoint to fail:
/// MockStore.instance.add(MockRule(
///   id: 'orders-500',
///   urlPattern: '/orders',
///   statusCode: 500,
///   body: '{"message": "boom"}',
/// ));
/// ```
class MockStore {
  MockStore._();
  static final MockStore instance = MockStore._();

  /// Set before the first request to persist rules across restarts:
  ///
  /// ```dart
  /// MockStore.instance.storage = SharedPreferencesMockRuleStorage();
  /// await MockStore.instance.load();
  /// ```
  MockRuleStorage storage = InMemoryMockRuleStorage();

  /// Kills mocking outright: no rule matches, offline mode is ignored, and the
  /// adapters stop consulting this store at all.
  ///
  /// **This is the only switch.** The Network page reads [isDisabled] and drops
  /// the Mocks button, "Mock this request" and the interception warning along
  /// with it — so there's no way to end up with the UI hidden while a rule added
  /// from code goes on faking traffic, which is what a separate UI-only flag
  /// used to allow.
  ///
  /// ```dart
  /// MockStore.instance.disable();   // before the first request
  /// ```
  bool _disabled = false;
  bool get isDisabled => _disabled;

  void disable() {
    _disabled = true;
    offline.value = false;
    rulesEnabled.value = false;
  }

  /// Undoes [disable]. Mostly for tests — the store is a singleton, so a test
  /// that disables it would otherwise poison every later test.
  void enable() {
    _disabled = false;
    rulesEnabled.value = true;
  }

  /// Master switch — every request fails as if the network were unreachable.
  /// Takes precedence over the rules.
  final ValueNotifier<bool> offline = ValueNotifier(false);

  /// Master switch for the rules. Lets you park a set of rules without deleting
  /// them.
  final ValueNotifier<bool> rulesEnabled = ValueNotifier(true);

  final ValueNotifier<List<MockRule>> rules = ValueNotifier(const []);

  /// True when anything is currently intercepting traffic. The Network page
  /// shows a warning banner on this, so a forgotten mock can't be mistaken for
  /// real server behaviour.
  bool get isIntercepting => !_disabled && (offline.value || (rulesEnabled.value && rules.value.any((r) => r.enabled)));

  /// The rule that should handle this request, or null to let it through.
  ///
  /// First enabled match wins, so order matters — a specific rule must sit
  /// above a broad one.
  MockRule? ruleFor({required String url, required String method}) {
    if (_disabled || !rulesEnabled.value) return null;
    for (final rule in rules.value) {
      if (rule.matches(url: url, method: method)) return rule;
    }
    return null;
  }

  void add(MockRule rule) {
    rules.value = [...rules.value, rule];
    save();
  }

  void update(MockRule rule) {
    rules.value = [
      for (final r in rules.value)
        if (r.id == rule.id) rule else r,
    ];
    save();
  }

  void remove(String id) {
    rules.value = rules.value.where((r) => r.id != id).toList();
    save();
  }

  void toggle(String id) {
    final rule = rules.value.firstWhere((r) => r.id == id);
    update(rule.copyWith(enabled: !rule.enabled));
  }

  void clear() {
    rules.value = const [];
    save();
  }

  /// Loads persisted rules. Call once at startup, after setting [storage].
  ///
  /// A corrupt payload is discarded rather than thrown — a debug tool must not
  /// take the app down on startup because its own scratch file went bad.
  Future<void> load() async {
    try {
      final raw = await storage.read();
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw) as List;
      rules.value = decoded.map((e) => MockRule.fromJson(e as Map<String, dynamic>)).toList();

      // The id counter restarts at 0 each run, so seed it past everything we
      // just loaded — otherwise the next new rule collides with a persisted one
      // and update()/remove() would hit the wrong rule.
      for (final rule in rules.value) {
        final n = int.tryParse(rule.id.replaceFirst('rule-', ''));
        if (n != null && n >= _nextId) _nextId = n + 1;
      }
    } catch (e) {
      debugPrint('devtray: could not load mock rules ($e) — starting empty');
      rules.value = const [];
    }
  }

  Future<void> save() async {
    try {
      await storage.write(jsonEncode(rules.value.map((r) => r.toJson()).toList()));
    } catch (e) {
      debugPrint('devtray: could not save mock rules ($e)');
    }
  }

  /// Generates an id for a new rule. Not time-based — a monotonic counter is
  /// enough and keeps the store deterministic under test.
  String nextId() => 'rule-${_nextId++}';
  int _nextId = 0;
}
