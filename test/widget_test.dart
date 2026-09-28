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
}
