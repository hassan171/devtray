import 'package:devtray/devtray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final store = DevtrayLog.instance;

  setUp(() {
    // The store is a singleton, so every one of these leaks into the next test
    // if it isn't reset — which is how the enricher from one test ended up
    // decorating another's entries.
    store
      ..clear()
      ..clearContext()
      ..clearEnrichers();
  });

  tearDown(() {
    store
      ..clearContext()
      ..clearEnrichers();
  });

  group('per-call fields', () {
    test('are carried on the entry', () {
      store.log('checkout failed', fields: {'cartId': 42, 'step': 'payment'});

      expect(store.entries.single.fields, {'cartId': 42, 'step': 'payment'});
    });

    test('are attached to reported errors too', () {
      store.report(StateError('boom'), fields: {'orderId': 7});

      expect(store.entries.single.fields['orderId'], 7);
    });

    test('cost nothing when unused — no allocation per entry', () {
      store
        ..log('a')
        ..log('b');

      // Shared const map. The default path is by far the most common one, and
      // it must not allocate per line.
      expect(identical(store.entries[0].fields, store.entries[1].fields), isTrue);
      expect(store.entries.first.fields, isEmpty);
    });
  });

  group('ambient context', () {
    test('attaches to every subsequent entry', () {
      store
        ..setContext('userId', 'u-1')
        ..log('first')
        ..log('second');

      expect(store.entries[0].fields['userId'], 'u-1');
      expect(store.entries[1].fields['userId'], 'u-1');
    });

    test('does not retroactively apply to entries already logged', () {
      store
        ..log('before')
        ..setContext('screen', 'checkout')
        ..log('after');

      final before = store.entries.firstWhere((e) => e.message == 'before');
      expect(before.fields, isEmpty, reason: 'a line logged before the context was set never had it');
    });

    test('an entry keeps the values current when it was logged', () {
      store
        ..setContext('screen', 'home')
        ..log('on home')
        ..setContext('screen', 'settings')
        ..log('on settings');

      // The failure this guards: holding a reference to the live context map
      // would make every past line claim it happened on the current screen.
      final onHome = store.entries.firstWhere((e) => e.message == 'on home');
      expect(onHome.fields['screen'], 'home');
    });

    test('unchanged context is shared, not copied per entry', () {
      store
        ..setContext('build', '1.0.0')
        ..log('a')
        ..log('b');

      expect(
        identical(store.entries[0].fields, store.entries[1].fields),
        isTrue,
        reason: 'context set once must be free per line, however many lines there are',
      );
    });

    test('removeContext and clearContext stop the attachment', () {
      store
        ..setContext('a', 1)
        ..setContext('b', 2)
        ..removeContext('a')
        ..log('one');

      expect(store.entries.first.fields, {'b': 2});

      store
        ..clearContext()
        ..log('two');

      expect(store.entries.first.fields, isEmpty);
    });

    test('clearing logs does not clear context — that is configuration, not data', () {
      store
        ..setContext('userId', 'u-1')
        ..clear()
        ..log('after clear');

      expect(store.entries.single.fields['userId'], 'u-1');
    });

    group('withContext', () {
      test('applies inside the scope and restores after', () async {
        await store.withContext({'orderId': 9}, () async {
          store.log('inside');
        });
        store.log('outside');

        final inside = store.entries.firstWhere((e) => e.message == 'inside');
        final outside = store.entries.firstWhere((e) => e.message == 'outside');

        expect(inside.fields['orderId'], 9);
        expect(outside.fields.containsKey('orderId'), isFalse);
      });

      test('restores a shadowed outer value rather than deleting the key', () async {
        store.setContext('screen', 'home');

        await store.withContext({'screen': 'modal'}, () async {
          store.log('in modal');
        });
        store.log('back home');

        expect(store.entries.firstWhere((e) => e.message == 'in modal').fields['screen'], 'modal');
        expect(
          store.entries.firstWhere((e) => e.message == 'back home').fields['screen'],
          'home',
          reason: 'nesting must not destroy the outer scope',
        );
      });

      test('restores even when the body throws', () async {
        await expectLater(
          store.withContext({'txn': 'abc'}, () async => throw StateError('failed')),
          throwsStateError,
        );

        store.log('after');
        expect(store.entries.first.fields.containsKey('txn'), isFalse);
      });
    });
  });

  group('enrichers', () {
    test('compute fields fresh on every entry', () {
      var route = '/home';
      store.addEnricher('nav', () => {'route': route});

      store.log('first');
      route = '/settings';
      store.log('second');

      expect(store.entries.firstWhere((e) => e.message == 'first').fields['route'], '/home');
      expect(store.entries.firstWhere((e) => e.message == 'second').fields['route'], '/settings');
    });

    test('registering the same name twice replaces it', () {
      store
        ..addEnricher('x', () => {'v': 1})
        ..addEnricher('x', () => {'v': 2})
        ..log('once');

      expect(store.entries.single.fields['v'], 2);
    });

    test('removeEnricher stops it', () {
      store
        ..addEnricher('x', () => {'v': 1})
        ..removeEnricher('x')
        ..log('after');

      expect(store.entries.single.fields.containsKey('v'), isFalse);
    });

    test('a throwing enricher never costs the log line', () {
      store
        ..addEnricher('bad', () => throw StateError('no route yet'))
        ..log('important');

      final entry = store.entries.firstWhere((e) => e.message == 'important');
      expect(entry, isNotNull, reason: 'the line survives its decoration failing');
      expect('${entry.fields['bad!']}', contains('no route yet'), reason: 'and says why the field is missing');
    });

    test('a persistently failing enricher is dropped and reported', () async {
      store.addEnricher('bad', () => throw StateError('always'));

      store
        ..log('one')
        ..log('two');

      expect(store.failedEnrichers.keys, contains('bad'));

      // The removal notice is queued, not logged inline — logging from inside
      // _add would re-enter it.
      await Future<void>.delayed(Duration.zero);
      expect(
        store.entries.any((e) => e.tag == 'devtray' && e.message.contains('was removed')),
        isTrue,
      );

      store.log('three');
      expect(
        store.entries.firstWhere((e) => e.message == 'three').fields.containsKey('bad!'),
        isFalse,
        reason: 'a broken enricher must not write its error onto every line forever',
      );
    });
  });

  group('precedence', () {
    test('call fields beat enrichers beat ambient context', () {
      store
        ..setContext('who', 'ambient')
        ..setContext('ambientOnly', true)
        ..addEnricher('e', () => {'who': 'enricher', 'enricherOnly': true})
        ..log('line', fields: {'who': 'call', 'callOnly': true});

      final f = store.entries.single.fields;

      // The more specific the source, the more it knows.
      expect(f['who'], 'call');
      expect(f['ambientOnly'], true);
      expect(f['enricherOnly'], true);
      expect(f['callOnly'], true);
    });
  });

  group('search and serialisation', () {
    test('search matches both field keys and values', () {
      store.log('nothing distinctive here', fields: {'userId': 4821});

      final entry = store.entries.single;
      expect(entry.searchable, contains('userid'));
      expect(entry.searchable, contains('4821'), reason: '"the line that mentions 4821" is the common query');
    });

    test('fields round-trip through the JSON format', () {
      store.log('with fields', fields: {'userId': 'u-1', 'count': 3, 'flag': true});
      final original = store.entries.single;

      final parsed = parseLogEntries(formatLogEntryAsJson(original)).single;

      expect(parsed.fields['userId'], 'u-1');
      expect(parsed.fields['count'], 3, reason: 'numbers stay numbers');
      expect(parsed.fields['flag'], true);
    });

    test('an un-encodable field value does not lose the whole line', () {
      store.log('has an object', fields: {'user': Object()});

      // One bad value must not fail jsonEncode for the entry — the alternative
      // is losing the line entirely, or silently dropping the context that was
      // worth capturing.
      final parsed = parseLogEntries(formatLogEntryAsJson(store.entries.single)).single;

      expect(parsed.message, 'has an object');
      expect(parsed.fields['user'], isA<String>());
    });

    test('the text format puts fields on the message line', () {
      store.log('request failed', fields: {'status': 500});

      expect(formatLogEntryAsText(store.entries.single), contains('{status=500}'));
    });

    test('an error report carries fields into its plain-text form', () {
      store.report(StateError('boom'), fields: {'userId': 'u-9'});

      expect(errorAsPlainText(store.entries.single), contains('userId: u-9'));
    });
  });

  group('the detail dialog', () {
    Future<void> openDetail(WidgetTester tester, LogEntry entry) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DevtrayThemeScope(
            theme: const DevtrayTheme(),
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => LogDetailDialog.show(context, entry),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows Fields exactly once on an ERROR entry', (tester) async {
      store.report(StateError('boom'), fields: {'userId': 'u-9'});

      await openDetail(tester, store.entries.single);

      // The bug: ErrorDetailSections renders its own Fields section, so a
      // second one after the branch meant errors showed it twice.
      expect(find.text('Fields'), findsOneWidget);
    });

    testWidgets('shows Fields exactly once on a PLAIN entry', (tester) async {
      store.log('ordinary line', fields: {'cartId': 42});

      await openDetail(tester, store.entries.single);

      expect(find.text('Fields'), findsOneWidget);
      expect(find.textContaining('cartId: 42'), findsWidgets);
    });

    testWidgets('shows no Fields section when there are none', (tester) async {
      store.log('bare line');

      await openDetail(tester, store.entries.single);

      expect(find.text('Fields'), findsNothing);
    });
  });
}
