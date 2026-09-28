// Schedule maths for weekly / monthly / yearly recurring entries.
// Run: flutter test test/recurring_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:expensetracker/models/recurring_entry.dart';

RecurringEntry _entry(RecurringFrequency f,
        {int day = 1, int weekday = 1, int month = 1}) =>
    RecurringEntry(
      id: 't',
      type: RecurringType.expense,
      title: 'Test',
      amount: 100,
      frequency: f,
      dayOfMonth: day,
      weekday: weekday,
      month: month,
      nextDue: DateTime(2026, 9, 28),
    );

void main() {
  group('monthly', () {
    test('31st falls back to the last day of short months', () {
      final e = _entry(RecurringFrequency.monthly, day: 31);
      expect(e.nextAfter(DateTime(2027, 1, 31)), DateTime(2027, 2, 28));
      expect(e.nextAfter(DateTime(2027, 2, 28)), DateTime(2027, 3, 31));
    });

    test('next occurrence on or after a date', () {
      final e = _entry(RecurringFrequency.monthly, day: 5);
      expect(e.occurrenceOnOrAfter(DateTime(2026, 9, 28)), DateTime(2026, 10, 5));
      expect(e.occurrenceOnOrAfter(DateTime(2026, 10, 5)), DateTime(2026, 10, 5));
    });
  });

  group('weekly', () {
    test('occurrence in the current week (Sunday start by default)', () {
      final e = _entry(RecurringFrequency.weekly, weekday: DateTime.monday);
      // Wed 30 Sep 2026 -> Mon 28 Sep 2026
      expect(e.occurrenceInPeriodOf(DateTime(2026, 9, 30)), DateTime(2026, 9, 28));
      // Sun 27 Sep starts the week, so this week's Monday is tomorrow.
      expect(e.occurrenceInPeriodOf(DateTime(2026, 9, 27)), DateTime(2026, 9, 28));
      // "Every Sunday" seen on Sat 3 Oct: this week's Sunday was 27 Sep.
      final sun = _entry(RecurringFrequency.weekly, weekday: DateTime.sunday);
      expect(sun.occurrenceInPeriodOf(DateTime(2026, 10, 3)), DateTime(2026, 9, 27));
      expect(sun.occurrenceOnOrAfter(DateTime(2026, 10, 3)), DateTime(2026, 10, 4));
    });

    test('rolls to next week once the day has passed', () {
      final e = _entry(RecurringFrequency.weekly, weekday: DateTime.monday);
      expect(e.occurrenceOnOrAfter(DateTime(2026, 9, 29)), DateTime(2026, 10, 5));
      expect(e.nextAfter(DateTime(2026, 10, 5)), DateTime(2026, 10, 12));
    });
  });

  group('yearly', () {
    test('next year once this year\'s date has passed', () {
      final e = _entry(RecurringFrequency.yearly, day: 5, month: 3);
      expect(e.occurrenceOnOrAfter(DateTime(2026, 9, 28)), DateTime(2027, 3, 5));
      expect(e.nextAfter(DateTime(2027, 3, 5)), DateTime(2028, 3, 5));
    });

    test('29 Feb falls back to 28 Feb in non-leap years', () {
      final e = _entry(RecurringFrequency.yearly, day: 29, month: 2);
      expect(e.nextAfter(DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
    });
  });

  test('schedule labels', () {
    expect(_entry(RecurringFrequency.weekly, weekday: 1).scheduleLabel,
        'Every Monday');
    expect(_entry(RecurringFrequency.monthly, day: 5).scheduleLabel,
        '5th of every month');
    expect(_entry(RecurringFrequency.yearly, day: 5, month: 3).scheduleLabel,
        'Every year on 5 Mar');
  });

  test('saved entries keep their schedule; old ones read as monthly', () {
    final e = _entry(RecurringFrequency.weekly, weekday: 3);
    final back = RecurringEntry.fromJson(e.toJson());
    expect(back.frequency, RecurringFrequency.weekly);
    expect(back.weekday, 3);

    final old = Map<String, dynamic>.from(e.toJson())
      ..remove('frequency')
      ..remove('weekday')
      ..remove('month');
    expect(RecurringEntry.fromJson(old).frequency, RecurringFrequency.monthly);
  });
}
