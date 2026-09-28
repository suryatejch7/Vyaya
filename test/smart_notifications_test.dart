import 'package:flutter_test/flutter_test.dart';
import 'package:expensetracker/models/expense_models.dart';
import 'package:expensetracker/services/smart_notifications.dart';

Expense _e(double amount, String category, DateTime date, {String? tx}) =>
    Expense(
      amount: amount,
      description: 'x',
      category: category,
      date: date,
      transactionId: tx,
      createdAt: date,
      updatedAt: date,
    );

String _same(String c) => c;

void main() {
  group('nextWeeklyTime', () {
    test('Wednesday -> coming Sunday 1 PM', () {
      expect(SmartNotifications.nextWeeklyTime(DateTime(2026, 9, 30, 9)),
          DateTime(2026, 10, 4, 13));
    });
    test('Sunday morning -> same day 1 PM', () {
      expect(SmartNotifications.nextWeeklyTime(DateTime(2026, 10, 4, 9)),
          DateTime(2026, 10, 4, 13));
    });
    test('Sunday after 1 PM -> next Sunday', () {
      expect(SmartNotifications.nextWeeklyTime(DateTime(2026, 10, 4, 15)),
          DateTime(2026, 10, 11, 13));
    });
  });

  group('weeklyText', () {
    final sunday = DateTime(2026, 10, 4, 13); // summarises 27 Sep – 3 Oct

    test('totals last Sun–Sat, top category and change', () {
      final (title, body) = SmartNotifications.weeklyText([
        _e(300, 'Food', DateTime(2026, 9, 27, 10)), // Sun, in
        _e(200, 'Travel', DateTime(2026, 10, 3, 22)), // Sat, in
        _e(999, 'Food', DateTime(2026, 10, 4, 9)), // this Sunday, out
        _e(1000, 'Food', DateTime(2026, 9, 22)), // week before
        _e(700, 'Saved', DateTime(2026, 9, 30),
            tx: 'auto-saved-2026-09'), // not spending
      ], sunday, _same);
      expect(title, 'Last week: ₹500 spent');
      expect(body, contains('2 payments'));
      expect(body, contains('most on Food (₹300)'));
      expect(body, contains('↓50% vs the week before'));
    });

    test('nothing logged', () {
      final (title, body) = SmartNotifications.weeklyText([], sunday, _same);
      expect(title, 'Your week in Vyaya');
      expect(body, contains('No spending logged'));
    });
  });
}
