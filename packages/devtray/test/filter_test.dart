import 'package:devtray/devtray.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tiny record to filter over — enough to exercise every operator without
/// dragging real entries in.
class _Row {
  final String level;
  final String tag;
  final String message;
  const _Row(this.level, this.tag, this.message);
}

void main() {
  final fields = <String, FilterField<_Row>>{
    'Level': FilterField(name: 'Level', valueOf: (r) => r.level, suggestions: const ['ERR', 'INF']),
    'Tag': FilterField(name: 'Tag', valueOf: (r) => r.tag),
    'Message': FilterField(name: 'Message', valueOf: (r) => r.message),
  };

  final rows = const [
    _Row('ERR', 'network', 'HTTP 500 on /orders'),
    _Row('INF', 'auth', 'user signed in'),
    _Row('ERR', 'flutter', 'RenderFlex overflowed'),
    _Row('DBG', 'auth', 'token cached'),
  ];

  FilterCondition<_Row> cond(String field, FilterOp op, String value) =>
      FilterCondition<_Row>(field: field, op: op, value: value);

  List<_Row> run(List<FilterCondition<_Row>> cs) => applyFilter(rows, cs, fields);

  group('operators', () {
    test('equals is case-insensitive', () {
      expect(run([cond('Level', FilterOp.equals, 'err')]).length, 2);
    });

    test('notEquals excludes matches and keeps absent-field rows', () {
      // Every row has a Level, so notEquals ERR keeps the two non-ERR rows.
      expect(run([cond('Level', FilterOp.notEquals, 'ERR')]).map((r) => r.level), ['INF', 'DBG']);
    });

    test('contains / notContains', () {
      expect(run([cond('Message', FilterOp.contains, 'http')]).single.tag, 'network');
      expect(run([cond('Message', FilterOp.notContains, 'http')]).length, 3);
    });

    test('in / notIn split a comma list', () {
      expect(run([cond('Level', FilterOp.isIn, 'err, inf')]).length, 3);
      expect(run([cond('Level', FilterOp.notIn, 'err, inf')]).single.level, 'DBG');
    });

    test('regex matches, and an invalid pattern matches nothing', () {
      expect(run([cond('Message', FilterOp.regex, r'HTTP \d+')]).single.tag, 'network');
      expect(run([cond('Message', FilterOp.regex, '(')]), isEmpty);
    });
  });

  group('applyFilter', () {
    test('an incomplete condition is ignored (does not hide everything)', () {
      expect(run([cond('Level', FilterOp.equals, '')]).length, rows.length);
    });

    test('conditions are AND-ed', () {
      final r = run([
        cond('Level', FilterOp.equals, 'ERR'),
        cond('Tag', FilterOp.equals, 'flutter'),
      ]);
      expect(r.single.message, 'RenderFlex overflowed');
    });

    test('an unknown field with a positive op matches nothing', () {
      expect(run([cond('Nope', FilterOp.equals, 'x')]), isEmpty);
    });

    test('an unknown field with a negated op matches everything', () {
      expect(run([cond('Nope', FilterOp.notEquals, 'x')]).length, rows.length);
    });
  });
}
