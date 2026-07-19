
import 'package:devtray/devtray.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DevtrayMocks mocks;

  setUp(() {
    // Fresh singletons per test.
    mocks = DevtrayMocks.instance
      ..enable()
      ..clear()
      ..offline.value = false
      ..rulesEnabled.value = true;
    DevtrayNet.instance.clear();
    DevtrayLog.instance.clear();
  });

  group('MockRule.matches', () {
    test('substring matching on the URL', () {
      const rule = MockRule(id: 'r', urlPattern: '/orders');

      expect(rule.matches(url: 'https://api.test/v1/orders', method: 'GET'), isTrue);
      expect(rule.matches(url: 'https://api.test/v1/users', method: 'GET'), isFalse);
    });

    test('regex matching when opted in', () {
      const rule = MockRule(id: 'r', urlPattern: r'/users/\d+/orders$', isRegex: true);

      expect(rule.matches(url: 'https://api.test/users/42/orders', method: 'GET'), isTrue);
      expect(rule.matches(url: 'https://api.test/users/me/orders', method: 'GET'), isFalse);
    });

    test('an invalid regex never matches, rather than throwing', () {
      // A half-typed pattern in the editor must not blow up every request.
      const rule = MockRule(id: 'r', urlPattern: '[unclosed', isRegex: true);
      expect(rule.matches(url: 'https://api.test/x', method: 'GET'), isFalse);
    });

    test('method filter', () {
      const rule = MockRule(id: 'r', urlPattern: '/orders', method: 'POST');

      expect(rule.matches(url: 'https://api.test/orders', method: 'POST'), isTrue);
      expect(rule.matches(url: 'https://api.test/orders', method: 'GET'), isFalse);
    });

    test('a disabled rule never matches', () {
      const rule = MockRule(id: 'r', urlPattern: '/orders', enabled: false);
      expect(rule.matches(url: 'https://api.test/orders', method: 'GET'), isFalse);
    });

    test('an empty pattern matches nothing — not everything', () {
      // A blank field in the editor must not silently mock the whole app.
      const rule = MockRule(id: 'r', urlPattern: '');
      expect(rule.matches(url: 'https://api.test/anything', method: 'GET'), isFalse);
    });
  });

  group('decideMock', () {
    test('no rules → pass through', () {
      expect(decideMock(url: 'https://api.test/x', method: 'GET'), isA<PassThrough>());
    });

    test('offline beats everything', () {
      mocks
        ..add(const MockRule(id: 'r', urlPattern: '/x', statusCode: 200))
        ..offline.value = true;

      expect(decideMock(url: 'https://api.test/x', method: 'GET'), isA<FailWith>());
    });

    test('rulesEnabled=false parks the rules without deleting them', () {
      mocks
        ..add(const MockRule(id: 'r', urlPattern: '/x', statusCode: 500))
        ..rulesEnabled.value = false;

      expect(decideMock(url: 'https://api.test/x', method: 'GET'), isA<PassThrough>());
      expect(mocks.rules.value, hasLength(1)); // still there
    });

    test('first matching rule wins — order matters', () {
      mocks
        ..add(const MockRule(id: 'specific', urlPattern: '/orders/42', statusCode: 418))
        ..add(const MockRule(id: 'broad', urlPattern: '/orders', statusCode: 500));

      final d = decideMock(url: 'https://api.test/orders/42', method: 'GET');
      expect((d as RespondWith).statusCode, 418);
    });

    test('each action maps to the right decision', () {
      mocks.add(const MockRule(id: 'f', urlPattern: '/fail', action: MockAction.fail));
      expect(decideMock(url: 'https://api.test/fail', method: 'GET'), isA<FailWith>());

      mocks.clear();
      mocks.add(const MockRule(id: 'd', urlPattern: '/slow', action: MockAction.delayOnly, delay: Duration(seconds: 1)));
      final d = decideMock(url: 'https://api.test/slow', method: 'GET');
      expect(d, isA<PassThrough>());
      expect((d as PassThrough).delay, const Duration(seconds: 1));
    });
  });

  group('MockRule.decodedBody', () {
    test('parses JSON', () {
      const rule = MockRule(id: 'r', urlPattern: '/x', body: '{"a": 1}');
      expect(rule.decodedBody, {'a': 1});
    });

    test('falls back to the raw string when it is not JSON', () {
      const rule = MockRule(id: 'r', urlPattern: '/x', body: 'plain text');
      expect(rule.decodedBody, 'plain text');
    });

    test('empty body is null', () {
      expect(const MockRule(id: 'r', urlPattern: '/x').decodedBody, isNull);
    });
  });


  group('persistence', () {
    test('rules round-trip through storage', () async {
      final storage = InMemoryMockRuleStorage();
      mocks.storage = storage;
      addTearDown(() => mocks.storage = InMemoryMockRuleStorage());

      mocks.add(const MockRule(
        id: 'rule-7',
        urlPattern: '/orders',
        method: 'POST',
        isRegex: true,
        statusCode: 418,
        body: '{"a":1}',
        delay: Duration(milliseconds: 250),
      ));

      // Simulate a restart: wipe memory, reload from the same storage.
      mocks.rules.value = const [];
      await mocks.load();

      final rule = mocks.rules.value.single;
      expect(rule.id, 'rule-7');
      expect(rule.urlPattern, '/orders');
      expect(rule.method, 'POST');
      expect(rule.isRegex, isTrue);
      expect(rule.statusCode, 418);
      expect(rule.body, '{"a":1}');
      expect(rule.delay, const Duration(milliseconds: 250));
    });

    test('the id counter is seeded past loaded rules, so new ids do not collide', () async {
      final storage = InMemoryMockRuleStorage();
      mocks.storage = storage;
      addTearDown(() => mocks.storage = InMemoryMockRuleStorage());

      mocks.add(const MockRule(id: 'rule-5', urlPattern: '/a'));
      mocks.rules.value = const [];
      await mocks.load();

      // Without seeding, nextId() would restart at rule-0 and eventually reissue
      // rule-5, so update()/remove() would hit the wrong rule.
      expect(mocks.nextId(), isNot('rule-5'));
      expect(int.parse(mocks.nextId().replaceFirst('rule-', '')), greaterThan(5));
    });

    test('corrupt stored data is discarded, not thrown', () async {
      final storage = InMemoryMockRuleStorage();
      await storage.write('this is not json');
      mocks.storage = storage;
      addTearDown(() => mocks.storage = InMemoryMockRuleStorage());

      // A debug tool must not take the app down because its scratch file rotted.
      await mocks.load();
      expect(mocks.rules.value, isEmpty);
    });
  });

  group('isIntercepting', () {
    test('reports whether anything is currently faking traffic', () {
      expect(mocks.isIntercepting, isFalse);

      mocks.add(const MockRule(id: 'r', urlPattern: '/x'));
      expect(mocks.isIntercepting, isTrue);

      mocks.toggle('r');
      expect(mocks.isIntercepting, isFalse, reason: 'the only rule is now disabled');

      mocks.offline.value = true;
      expect(mocks.isIntercepting, isTrue);
    });
  });
}
