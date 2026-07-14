import 'dart:io';

import 'package:debug_overlay/debug_overlay.dart';
import 'package:debug_overlay_example/users_box.dart';
import 'package:debug_overlay_example/users_debug_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

Widget _host() => const MaterialApp(
      home: Scaffold(
        body: DebugToolsScreen(pages: [UsersDebugPage()]),
      ),
    );

const ada = User(
  id: 1,
  name: 'Ada Lovelace',
  username: 'ada',
  email: 'ada@example.com',
  city: 'London',
);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('debug_overlay_users_page_test');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UserAdapter());
    await Hive.openBox<User>(usersBoxName);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('an empty box points you at the fetch button', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.textContaining('Empty'), findsOneWidget);
  });

  testWidgets('lists cached users', (tester) async {
    await usersBox.put('1', ada);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.textContaining('@ada'), findsOneWidget);
    expect(find.text('London'), findsOneWidget);
    expect(find.textContaining('1 cached in Hive'), findsOneWidget);
  });

  group('editing', () {
    testWidgets('each field gets its own input — not one blob to re-type', (tester) async {
      await usersBox.put('1', ada);

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      // Four separate fields, prefilled — you edit, you don't author.
      expect(find.widgetWithText(TextField, 'Ada Lovelace'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'ada'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'ada@example.com'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'London'), findsOneWidget);
    });

    testWidgets('saving writes back to the typed box, and the list updates live', (tester) async {
      await usersBox.put('1', ada);

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Ada Lovelace'), 'Grace Hopper');
      await tester.enterText(find.widgetWithText(TextField, 'London'), 'New York');
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();

      // The box is the source of truth.
      final stored = usersBox.get('1')!;
      expect(stored.name, 'Grace Hopper');
      expect(stored.city, 'New York');
      expect(stored.username, 'ada', reason: 'untouched fields survive');
      expect(stored.id, 1, reason: 'the id is the key, not editable');

      // And the page reacts via Hive's listenable — no manual refresh.
      expect(find.text('Grace Hopper'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsNothing);
    });

    testWidgets('cancel discards the edit', (tester) async {
      await usersBox.put('1', ada);

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Ada Lovelace'), 'Nope');
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(usersBox.get('1')!.name, 'Ada Lovelace');
      expect(find.text('Ada Lovelace'), findsOneWidget);

      // Reopening the editor shows the stored value again, not the abandoned one.
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Ada Lovelace'), findsOneWidget);
    });
  });

  group('deleting', () {
    testWidgets('removes the user from the box and the list', (tester) async {
      await usersBox.put('1', ada);

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(usersBox.get('1'), isNull);
      expect(find.text('Ada Lovelace'), findsNothing);
      expect(find.textContaining('Empty'), findsOneWidget);
    });

    testWidgets('Clear box empties it', (tester) async {
      // copyWith deliberately can't change the id — it's the key — so build the
      // second user directly.
      const alan = User(id: 2, name: 'Alan Turing', username: 'alan', email: 'alan@example.com', city: 'Wilmslow');
      await usersBox.putAll({'1': ada, '2': alan});

      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clear box'));
      await tester.pumpAndSettle();

      expect(usersBox.isEmpty, isTrue);
      expect(find.textContaining('Empty'), findsOneWidget);
    });
  });
}
