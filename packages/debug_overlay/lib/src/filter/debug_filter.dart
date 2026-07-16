import 'package:flutter/foundation.dart';

/// One condition's comparison operator.
///
/// Ported from hapster's log filter, but generalised: hapster compared strings
/// pulled out of a formatted text block; here each [FilterField] pulls a real
/// value off a structured entry, so `matches` works against typed data.
enum FilterOp {
  equals('='),
  notEquals('≠'),
  contains('contains'),
  notContains('!contains'),
  isIn('in'),
  notIn('not in'),
  regex('matches');

  final String label;
  const FilterOp(this.label);

  bool get isMultiValue => this == isIn || this == notIn;
  bool get isNegated => this == notEquals || this == notContains || this == notIn;
}

/// A filterable dimension of an entry `T` — "Level", "Tag", "Message", "Time".
///
/// [valueOf] returns the entry's value for this field as a string (that's what
/// the operators compare against). [suggestions] offers a value picker for
/// enum-like fields; empty means free text.
@immutable
class FilterField<T> {
  final String name;
  final String Function(T entry) valueOf;
  final List<String> suggestions;

  const FilterField({required this.name, required this.valueOf, this.suggestions = const []});
}

/// A single `<field> <op> <value>` clause. Mutable — the pill UI edits it in
/// place, exactly like hapster's `LogCondition`.
class FilterCondition<T> {
  /// The chosen field's name, or empty until one is picked.
  String field;
  FilterOp op;

  /// Free-text value; for in/notIn it's comma-separated.
  String value;

  FilterCondition({this.field = '', this.op = FilterOp.equals, this.value = ''});

  bool get isComplete => field.isNotEmpty && value.trim().isNotEmpty;

  /// Tests this condition against [entry], resolving the field via [fields].
  /// An unknown/absent field → no match, except negated ops, which treat
  /// "absent" as "not equal" → match (same rule hapster used).
  bool matches(T entry, Map<String, FilterField<T>> fields) {
    final f = fields[field];
    if (f == null) return op.isNegated;

    final actual = f.valueOf(entry);
    final a = actual.toLowerCase();
    final v = value.trim().toLowerCase();

    switch (op) {
      case FilterOp.equals:
        return a == v;
      case FilterOp.notEquals:
        return a != v;
      case FilterOp.contains:
        return a.contains(v);
      case FilterOp.notContains:
        return !a.contains(v);
      case FilterOp.isIn:
        return _values.contains(a);
      case FilterOp.notIn:
        return !_values.contains(a);
      case FilterOp.regex:
        try {
          return RegExp(value, caseSensitive: false).hasMatch(actual);
        } catch (_) {
          return false; // an invalid regex matches nothing
        }
    }
  }

  List<String> get _values => value.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
}

/// AND-s a set of conditions over a list. Incomplete conditions are ignored,
/// so a half-typed pill doesn't hide everything.
List<T> applyFilter<T>(List<T> entries, List<FilterCondition<T>> conditions, Map<String, FilterField<T>> fields) {
  final active = conditions.where((c) => c.isComplete).toList();
  if (active.isEmpty) return entries;
  return entries.where((e) => active.every((c) => c.matches(e, fields))).toList();
}
