import 'package:debug_overlay/debug_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-memory adapter, so the tests exercise the page rather than a plugin.
class _FakeAdapter extends DebugStorageAdapter {
  @override
  final String name;
  @override
  final bool writable;

  final Map<String, Object?> store;

  /// Records exactly what the editor handed us — the type matters as much as the
  /// value.
  final List<({String key, Object? value})> writes = [];
  final List<String> deletes = [];

  _FakeAdapter(this.store, {this.writable = true}) : name = 'Fake';

  @override
  Future<Map<String, Object?>> readAll() async => Map.of(store);

  @override
  Future<void> write(String key, Object? value) async {
    writes.add((key: key, value: value));
    store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes.add(key);
    store.remove(key);
  }
}

class _ThrowingAdapter extends DebugStorageAdapter {
  @override
  String get name => 'Broken';

  @override
  Future<Map<String, Object?>> readAll() async => throw StateError('box not open');

  @override
  Future<void> write(String key, Object? value) async {}

  @override
  Future<void> delete(String key) async {}
}

Widget _host(List<DebugStorageAdapter> adapters) => MaterialApp(
      home: Scaffold(
        body: DebugToolsScreen(pages: [StorageDebugPage(adapters: adapters)]),
      ),
    );

void main() {
  group('reading', () {
    testWidgets('lists every key, with its type', (tester) async {
      final adapter = _FakeAdapter({
        'seen_onboarding': true,
        'retry_count': 3,
        'api_url': 'https://api.test',
      });

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      expect(find.text('seen_onboarding'), findsOneWidget);
      expect(find.text('retry_count'), findsOneWidget);
      expect(find.text('api_url'), findsOneWidget);

      // The type is shown, because it's what constrains what you can put back.
      expect(find.text('bool'), findsOneWidget);
      expect(find.text('int'), findsOneWidget);
      expect(find.text('String'), findsOneWidget);
    });

    testWidgets('a failing adapter reports its error, and does not take the page down', (tester) async {
      await tester.pumpWidget(_host([_ThrowingAdapter(), _FakeAdapter({'ok': 'yes'})]));
      await tester.pumpAndSettle();

      expect(find.textContaining('box not open'), findsOneWidget);
      // The working section still renders.
      expect(find.text('ok'), findsOneWidget);
    });

    testWidgets('search filters keys', (tester) async {
      await tester.pumpWidget(_host([
        _FakeAdapter({'api_url': 'x', 'user_id': 'y'}),
      ]));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'api');
      await tester.pumpAndSettle();

      expect(find.text('api_url'), findsOneWidget);
      expect(find.text('user_id'), findsNothing);
    });
  });

  group('read-only adapters', () {
    testWidgets('writable: false hides the edit and delete controls', (tester) async {
      await tester.pumpWidget(_host([
        _FakeAdapter({'api_url': 'x'}, writable: false),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('read-only'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.byTooltip('Delete'), findsNothing);
    });
  });

  group('editing preserves the value type', () {
    // This is the whole safety story. SharedPreferences has a setter per type and
    // throws on the next READ if you wrote the wrong one — an editor that turned
    // everything into a String would be a landmine.

    testWidgets('a String stays a String', (tester) async {
      final adapter = _FakeAdapter({'api_url': 'https://old.test'});

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'https://new.test');
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(adapter.writes.single.value, 'https://new.test');
      expect(adapter.writes.single.value, isA<String>());
    });

    testWidgets('an int stays an int', (tester) async {
      final adapter = _FakeAdapter({'retry_count': 3});

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '7');
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(adapter.writes.single.value, 7);
      expect(adapter.writes.single.value, isA<int>());
    });

    testWidgets('a bool gets a switch, not a text field', (tester) async {
      final adapter = _FakeAdapter({'seen_onboarding': true});

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      // No edit button — the switch IS the editor.
      expect(find.byTooltip('Edit'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(adapter.writes.single.value, false);
      expect(adapter.writes.single.value, isA<bool>());
    });

  });

  group('a List is edited as chips, not raw JSON', () {
    // Hand-editing `["flutter","dart"]` on a phone is the authoring-from-scratch
    // problem worth avoiding, and it made "Invalid JSON" a failure you could hit
    // by mistyping a bracket. With chips, a malformed list is unrepresentable.

    testWidgets('renders one chip per element, and no Edit button', (tester) async {
      await tester.pumpWidget(_host([
        _FakeAdapter({
          'tags': ['flutter', 'dart'],
        }),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('flutter'), findsOneWidget);
      expect(find.text('dart'), findsOneWidget);
      // The chips ARE the editor — no Edit/Save step, like a bool's switch.
      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('adding a chip writes back a List<String>', (tester) async {
      final adapter = _FakeAdapter({
        'tags': ['flutter'],
      });

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'dart');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(adapter.writes.single.value, ['flutter', 'dart']);
      // The type must survive — SharedPreferences throws on the next read
      // otherwise.
      expect(adapter.writes.single.value, isA<List<String>>());
    });

    testWidgets('tapping a chip renames it', (tester) async {
      final adapter = _FakeAdapter({
        'tags': ['flutter', 'dart'],
      });

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('dart'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'rust');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(adapter.writes.single.value, ['flutter', 'rust']);
    });

    testWidgets('the ✕ on a chip removes it', (tester) async {
      final adapter = _FakeAdapter({
        'tags': ['flutter', 'dart'],
      });

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      // Second chip's remove button.
      await tester.tap(find.byTooltip('Remove').last);
      await tester.pumpAndSettle();

      expect(adapter.writes.single.value, ['flutter']);
    });

    testWidgets('renaming a chip to empty removes it', (tester) async {
      final adapter = _FakeAdapter({
        'tags': ['flutter', 'dart'],
      });

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('dart'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(adapter.writes.single.value, ['flutter']);
    });

    testWidgets('an empty new chip is just a cancelled add — nothing written', (tester) async {
      final adapter = _FakeAdapter({
        'tags': ['flutter'],
      });

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(adapter.writes, isEmpty);
    });

    testWidgets('an empty list still offers Add', (tester) async {
      final adapter = _FakeAdapter({'tags': <String>[]});

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'first');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(adapter.writes.single.value, ['first']);
    });

    testWidgets('a read-only list shows no chips controls', (tester) async {
      await tester.pumpWidget(_host([
        _FakeAdapter({
          'tags': ['flutter'],
        }, writable: false),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('flutter'), findsOneWidget);
      expect(find.text('Add'), findsNothing);
      expect(find.byTooltip('Remove'), findsNothing);
    });
  });

  group('rejecting bad input', () {
    testWidgets('a non-numeric value is refused for an int, and NOT written', (tester) async {
      final adapter = _FakeAdapter({'retry_count': 3});

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'not a number');
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Not an int'), findsOneWidget);
      // The store is untouched — this is what stops you bricking the app.
      expect(adapter.writes, isEmpty);
      expect(adapter.store['retry_count'], 3);
    });

  });

  group('deleting', () {
    testWidgets('removes the key', (tester) async {
      final adapter = _FakeAdapter({'api_url': 'x'});

      await tester.pumpWidget(_host([adapter]));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(adapter.deletes, ['api_url']);
      expect(find.text('api_url'), findsNothing);
      expect(find.text('Empty'), findsOneWidget);
    });
  });
}
