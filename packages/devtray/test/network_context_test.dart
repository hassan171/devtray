import 'package:devtray/devtray.dart';
// Not exported from the barrel — the pane is internal to the Network page.
import 'package:devtray/src/network/components/network_detail_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NetworkLogEntry _request([String path = '/orders']) =>
    DevtrayNet.instance.add(method: 'GET', uri: Uri.parse('https://api.test$path'))!;

void main() {
  setUp(() {
    Devtray.reset();
    DevtrayLog.instance
      ..clear()
      ..clearContext()
      ..clearEnrichers();
    DevtrayNet.instance
      ..clear()
      ..excludedUrlPatterns.clear();
  });

  group('ambient context on network entries', () {
    test('a request carries the context that was set when it was made', () {
      Devtray.setContext('screen', 'Checkout');
      Devtray.setContext('build', '1.4.2');

      expect(_request().fields, {'screen': 'Checkout', 'build': '1.4.2'});
    });

    test('enrichers run for requests, not just log lines', () {
      var screen = 'Home';
      DevtrayLog.instance.addEnricher('nav', () => {'screen': screen});

      expect(_request().fields['screen'], 'Home');

      // The point of an enricher over plain context: it is read fresh, so it is
      // right for the request rather than for whenever it was last set.
      screen = 'Cart';
      expect(_request().fields['screen'], 'Cart');
    });

    test('per-call fields beat enrichers, which beat ambient context', () {
      Devtray.setContext('layer', 'ambient');
      DevtrayLog.instance.addEnricher('e', () => {'layer': 'enricher'});

      final entry = DevtrayNet.instance.add(
        method: 'GET',
        uri: Uri.parse('https://api.test/x'),
        fields: {'layer': 'call'},
      )!;

      // The more specific the source, the more it knows.
      expect(entry.fields['layer'], 'call');
    });

    test('costs nothing when nothing is configured', () {
      expect(_request().fields, isEmpty);
    });

    test('context is captured at request time, not at completion', () {
      Devtray.setContext('screen', 'Checkout');
      final entry = _request();

      // A slow request routinely outlives the screen that fired it. The whole
      // value of this is answering "where did this come from", so a late read
      // would report the wrong screen precisely when it matters.
      Devtray.setContext('screen', 'Receipt');
      DevtrayNet.instance.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);

      expect(entry.fields['screen'], 'Checkout');
    });

    test('an entry keeps the values current when it was captured', () {
      Devtray.setContext('screen', 'A');
      final first = _request('/a');

      Devtray.setContext('screen', 'B');
      final second = _request('/b');

      // The snapshot is shared for efficiency but replaced on change, never
      // mutated — holding the live map would make every past entry report the
      // screen you are on now.
      expect(first.fields['screen'], 'A');
      expect(second.fields['screen'], 'B');
    });
  });

  group('shared registry', () {
    test('one enricher labels both a log line and a request', () {
      Devtray.setContext('flavor', 'staging');
      DevtrayLog.instance.addEnricher('nav', () => {'screen': 'Cart'});

      Devtray.log('added to cart');
      final entry = _request();

      final line = DevtrayLog.instance.entries.first;
      expect(line.fields, {'flavor': 'staging', 'screen': 'Cart'});
      expect(entry.fields, {'flavor': 'staging', 'screen': 'Cart'});
    });

    test('a throwing enricher costs neither the request nor the line', () {
      DevtrayLog.instance.addEnricher('bad', () => throw StateError('boom'));

      final entry = _request();

      // The failure becomes the field's value: visible on the entry it broke,
      // rather than silently missing.
      expect(entry.fields.keys, contains('bad!'));
      expect(entry.fields['bad!'], contains('boom'));
    });

    test('an enricher that keeps throwing is dropped', () {
      DevtrayLog.instance.addEnricher('bad', () => throw StateError('boom'));

      _request('/1');
      _request('/2');
      _request('/3');

      // Otherwise it would write its error onto every entry in the session.
      expect(DevtrayLog.instance.failedEnrichers.keys, contains('bad'));
      expect(_request('/4').fields, isEmpty);
    });
  });

  group('detail pane', () {
    testWidgets('shows the fields on their own Context tab, labelled', (tester) async {
      Devtray.setContext('screen', 'Checkout');
      final entry = _request();
      DevtrayNet.instance.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkDetailPane(entry: entry, onBack: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Not on the Request tab: there it read as something the app sent, next
      // to the real headers and body.
      expect(find.text('Context'), findsOneWidget);
      expect(find.textContaining('screen: Checkout'), findsNothing, reason: 'the tab is not selected yet');

      await tester.tap(find.text('Context'));
      await tester.pumpAndSettle();

      expect(find.textContaining('screen: Checkout'), findsOneWidget);
      // The label is the point — without it the tab is ambiguous in the same
      // way the old placement was.
      expect(find.textContaining('not sent to the server'), findsOneWidget);
    });

    testWidgets('shows no Fields section when there is no context', (tester) async {
      final entry = _request();
      DevtrayNet.instance.complete(entry.id, status: NetworkLogStatus.success, statusCode: 200);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkDetailPane(entry: entry, onBack: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // An empty tab is worse than none — it is a heading promising data.
      expect(find.text('Context'), findsNothing);
    });
  });
}
