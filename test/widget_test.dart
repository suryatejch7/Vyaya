// Widget tests for the undo bar shown after deleting or dismissing things.
// Run: flutter test test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expensetracker/widgets/undo_bar.dart';
import 'package:expensetracker/widgets/undo_snackbar.dart';

Widget _app() => MaterialApp(
      builder: (context, child) => UndoHost(child: child!),
      home: const Scaffold(body: SizedBox.expand()),
    );

void main() {
  tearDown(UndoController.dismiss);

  testWidgets('Undo restores and hides the bar', (tester) async {
    var undone = false;
    await tester.pumpWidget(_app());
    UndoController.show('Deleted "Lunch"', () => undone = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Deleted "Lunch"'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(undone, isTrue);
    expect(find.text('Deleted "Lunch"'), findsNothing);
  });

  testWidgets('Bar disappears by itself after 5 seconds', (tester) async {
    var undone = false;
    await tester.pumpWidget(_app());
    UndoController.show('Dismissed 3 payments', () => undone = true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Dismissed 3 payments'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1, milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Dismissed 3 payments'), findsNothing);
    expect(undone, isFalse);
  });

  testWidgets('Swiping the bar down dismisses it without undoing',
      (tester) async {
    var undone = false;
    await tester.pumpWidget(_app());
    UndoController.show('Removed 2 payments', () => undone = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.drag(find.text('Removed 2 payments'), const Offset(0, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Removed 2 payments'), findsNothing);
    expect(undone, isFalse);
  });

  testWidgets('A second action folds the bar into a bubble; nothing is lost',
      (tester) async {
    final undone = <String>[];
    await tester.pumpWidget(_app());
    UndoController.show('Dismissed "Swiggy"', () => undone.add('swiggy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Dismissed "Swiggy"'), findsOneWidget);

    UndoController.show('Dismissed "Uber"', () => undone.add('uber'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Bubble: no message, a count of 2.
    expect(find.text('Dismissed "Uber"'), findsNothing);
    expect(find.text('2'), findsOneWidget);

    // Tap opens it on the latest action; UNDO takes back only that one.
    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Dismissed "Uber"'), findsOneWidget);
    await tester.tap(find.text('UNDO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(undone, ['uber']);
    expect(find.text('Dismissed "Swiggy"'), findsOneWidget);

    UndoController.dismiss(); // no timer left running
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('Undo all takes everything back, newest first', (tester) async {
    final undone = <String>[];
    await tester.pumpWidget(_app());
    for (final n in ['a', 'b', 'c']) {
      UndoController.show('Dismissed $n', () => undone.add(n));
    }
    await tester.pump();
    UndoController.expand();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Undo all 3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(undone, ['c', 'b', 'a']);
    expect(find.text('UNDO'), findsNothing);
  });

  testWidgets('Each new action restarts the 5 seconds', (tester) async {
    await tester.pumpWidget(_app());
    UndoController.show('one', () {});
    await tester.pump(const Duration(seconds: 4));
    UndoController.show('two', () {});
    await tester.pump(const Duration(seconds: 4));
    expect(UndoController.state.value.count, 2);
    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    expect(UndoController.state.value.count, 0);
  });
}
