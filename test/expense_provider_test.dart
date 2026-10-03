// Money logic of ExpenseProvider on top of the real on-device store (with
// in-memory SharedPreferences): month-end savings, carry-forward, deletes
// that stay deleted, delete by date, batch delete + undo, recurring entries,
// lent/borrowed settlements and cached totals.
// Run: flutter test test/expense_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expensetracker/models/debt_entry.dart';
import 'package:expensetracker/models/expense_models.dart';
import 'package:expensetracker/models/recurring_entry.dart';
import 'package:expensetracker/providers/expense_provider.dart';
import 'package:expensetracker/services/app_prefs.dart';
import 'package:expensetracker/services/local_store.dart';

String _key(DateTime m) => '${m.year}-${m.month.toString().padLeft(2, '0')}';

/// A fresh store and a provider for a new user. [savingsFrom] sets the first
/// month month-end savings handle (normally the month the app was set up,
/// so past months are never touched).
Future<ExpenseProvider> _provider(
    {DateTime? savingsFrom, String mode = 'save'}) async {
  SharedPreferences.setMockInitialValues({});
  await LocalStore.initialize();
  // Drops anything a previous test left in the shared store.
  await LocalStore.resetAllData();
  await AppPrefs.instance.init();
  final user = await LocalStore.createUser('Test');
  final settings = await LocalStore.createDefaultUserSettings(user.id);
  if (savingsFrom != null) {
    await LocalStore.setMeta('savings_from', _key(savingsFrom),
        userId: user.id);
  }
  await LocalStore.setMeta('month_end_mode', mode, userId: user.id);
  final p = ExpenseProvider();
  await p.initializeWithUser(user.id, user.userName, settings);
  return p;
}

Expense _expense(double amount, DateTime date,
        {String category = 'Food', String description = 'Lunch'}) =>
    Expense(
      amount: amount,
      description: description,
      category: category,
      date: date,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

Income _income(double amount, DateTime date, {String title = 'Salary'}) =>
    Income(
      amount: amount,
      title: title,
      source: 'Job',
      date: date,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

List<Expense> _saved(ExpenseProvider p) =>
    p.expenses.where(ExpenseProvider.isAutoSavedEntry).toList();

List<Income> _carried(ExpenseProvider p) =>
    p.incomes.where(ExpenseProvider.isCarryForwardEntry).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month);
  final lastMonth = DateTime(now.year, now.month - 1);
  final twoMonthsAgo = DateTime(now.year, now.month - 2);
  final midLastMonth = DateTime(lastMonth.year, lastMonth.month, 10);

  group('month-end savings', () {
    test('a closed month\'s leftover goes into one Saved entry', () async {
      final p = await _provider(savingsFrom: twoMonthsAgo);
      await p.addIncome(_income(1000, midLastMonth));
      await p.addExpense(_expense(300, midLastMonth));

      final saved = _saved(p);
      expect(saved, hasLength(1));
      expect(saved.single.amount, closeTo(700, 0.001));
      expect(saved.single.category, ExpenseProvider.savedCategoryName);
      expect(saved.single.date,
          DateTime(lastMonth.year, lastMonth.month + 1, 0)); // last day
      expect(saved.single.transactionId, 'auto-saved-${_key(lastMonth)}');
    });

    test('the Saved entry follows later edits and goes when nothing is left',
        () async {
      final p = await _provider(savingsFrom: twoMonthsAgo);
      await p.addIncome(_income(1000, midLastMonth));
      await p.addExpense(_expense(300, midLastMonth));
      await p.addExpense(_expense(200, midLastMonth));
      expect(_saved(p).single.amount, closeTo(500, 0.001));

      await p.addExpense(_expense(600, midLastMonth)); // now overspent
      expect(_saved(p), isEmpty);
    });

    test('a Saved entry you delete stays deleted', () async {
      final p = await _provider(savingsFrom: twoMonthsAgo);
      await p.addIncome(_income(1000, midLastMonth));
      await p.deleteExpense(_saved(p).single.id!);
      expect(_saved(p), isEmpty);

      await p.addIncome(_income(500, midLastMonth));
      await p.runAutomations();
      expect(_saved(p), isEmpty);
    });

    test('months before savings started are never touched', () async {
      final p = await _provider(savingsFrom: thisMonth);
      await p.addIncome(_income(1000, midLastMonth));
      expect(_saved(p), isEmpty);
      expect(_carried(p), isEmpty);
    });

    test('carry mode moves the leftover into next month as income',
        () async {
      final p = await _provider(savingsFrom: twoMonthsAgo, mode: 'carry');
      await p.addIncome(_income(1000, midLastMonth));
      await p.addExpense(_expense(400, midLastMonth));

      expect(_saved(p), isEmpty);
      final carry = _carried(p);
      expect(carry, hasLength(1));
      expect(carry.single.amount, closeTo(600, 0.001));
      expect(carry.single.date, thisMonth); // the 1st of the next month
      expect(carry.single.tag, 'auto-carry-${_key(lastMonth)}');
    });
  });

  group('carried-over income', () {
    test('moving its date back into its own month changes nothing',
        () async {
      final p = await _provider(savingsFrom: twoMonthsAgo, mode: 'carry');
      await p.addIncome(_income(1000, midLastMonth));
      await p.addExpense(_expense(400, midLastMonth));
      final carry = _carried(p).single;
      await p.updateIncome(carry.copyWith(date: midLastMonth));
      await p.addExpense(_expense(1, thisMonth)); // any later save
      final after = _carried(p).single;
      expect(after.amount, closeTo(600, 0.001)); // not 1200, 1800...
      expect(after.date, thisMonth); // back on the 1st
    });
  });

  group('delete by date', () {
    test('removes entries in the range but not the automatic ones', () async {
      final p = await _provider(savingsFrom: twoMonthsAgo);
      await p.addIncome(_income(1000, midLastMonth));
      await p.addExpense(_expense(100, midLastMonth));
      await p.addExpense(_expense(50, DateTime(now.year, now.month, 1)));

      final first = DateTime(lastMonth.year, lastMonth.month, 1);
      final last = DateTime(lastMonth.year, lastMonth.month + 1, 0);
      final found = p.entriesInRange(first, last);
      expect(found.expenses, hasLength(1)); // not the Saved entry
      expect(found.incomes, hasLength(1));

      final n = await p.deleteRange(first, last);
      expect(n, 2);
      // The month is empty now, so its Saved entry went by itself.
      expect(_saved(p), isEmpty);
      // This month's expense is outside the range and stays.
      expect(p.expenses.where((e) => e.amount == 50), hasLength(1));
    });

    test('the end day is included', () async {
      final p = await _provider();
      final day = DateTime(now.year, now.month, 1);
      await p.addExpense(_expense(10, DateTime(day.year, day.month, 1, 23, 59)));
      expect(p.entriesInRange(day, day).expenses, hasLength(1));
    });
  });

  group('batch delete and undo', () {
    test('deleteMany then restore brings everything back in order', () async {
      final p = await _provider();
      final day = DateTime(now.year, now.month, 1);
      for (var i = 0; i < 30; i++) {
        await p.addExpense(_expense(i + 1.0, day.add(Duration(hours: i))));
      }
      final total = p.expenses.fold(0.0, (s, e) => s + e.amount);
      final gone = p.expenses.where((e) => e.amount > 10).toList();

      await p.deleteMany(expenseIds: [for (final e in gone) e.id!]);
      expect(p.expenses, hasLength(10));

      await p.restoreExpenses(gone);
      expect(p.expenses, hasLength(30));
      expect(p.expenses.fold(0.0, (s, e) => s + e.amount), closeTo(total, 1e-6));
      // Newest first, and every restored entry has its own new id.
      for (var i = 1; i < p.expenses.length; i++) {
        expect(p.expenses[i - 1].date.isBefore(p.expenses[i].date), isFalse);
      }
      expect(p.expenses.map((e) => e.id).toSet(), hasLength(30));
    });

    test('the store keeps the same entries as the screen', () async {
      final p = await _provider();
      final day = DateTime(now.year, now.month, 1);
      await p.addExpense(_expense(5, day));
      await p.addExpense(_expense(6, day));
      await p.deleteMany(
          expenseIds: [p.expenses.firstWhere((e) => e.amount == 5).id!]);
      await LocalStore.flush();
      final stored = await LocalStore.getExpenses(userId: p.userId);
      expect(stored.map((e) => e.id).toSet(),
          p.expenses.map((e) => e.id).toSet());
    });
  });

  group('cached totals', () {
    test('this month\'s category total updates right after a change',
        () async {
      final p = await _provider();
      final day = DateTime(now.year, now.month, 1);
      expect(p.getCategoryExpenses('Food'), 0);
      await p.addExpense(_expense(120, day));
      expect(p.getCategoryExpenses('Food'), closeTo(120, 0.001));
      await p.addExpense(_expense(30, day));
      expect(p.getCurrentMonthCategoryExpenses('Food'), closeTo(150, 0.001));
      await p.deleteExpense(p.expenses.firstWhere((e) => e.amount == 30).id!);
      expect(p.getCategoryExpenses('Food'), closeTo(120, 0.001));
    });

    test('periodSummary counts and totals by category', () async {
      final p = await _provider();
      final day = DateTime(now.year, now.month, 1);
      await p.addExpense(_expense(100, day));
      await p.addExpense(_expense(50, day));
      await p.addExpense(_expense(20, day, category: 'Transport'));
      final s = p.periodSummary(FilterPeriod.monthly);
      expect(s.count, 3);
      expect(s.total, closeTo(170, 0.001));
      expect(s.totals['Food'], closeTo(150, 0.001));
      expect(s.counts['Food'], 2);
      expect(s.counts['Transport'], 1);
    });

    test('rupees always', () async {
      final p = await _provider();
      expect(p.currency, '₹');
    });
  });

  group('recurring', () {
    test('missed months are added once and not again', () async {
      final p = await _provider();
      final start = DateTime(now.year, now.month - 2, 1);
      await p.addRecurring(RecurringEntry(
        id: 'rent',
        type: RecurringType.expense,
        title: 'Rent',
        amount: 5000,
        category: 'Bills',
        dayOfMonth: 1,
        nextDue: start,
      ));
      int rents() => p.expenses.where((e) => e.description == 'Rent').length;
      expect(rents(), 3); // two months ago, last month, this month (the 1st)
      expect(p.recurringEntries.single.nextDue,
          DateTime(now.year, now.month + 1, 1));

      await p.runAutomations();
      expect(rents(), 3);
    });
  });

  group('lent & borrowed', () {
    test('settling with a record logs income; reopening removes it',
        () async {
      final p = await _provider();
      await p.addDebt(DebtEntry(
        id: 'd1',
        person: 'Ravi',
        amount: 800,
        isLent: true,
        date: DateTime(now.year, now.month, 1),
      ));
      expect(p.totalOwedToYou, closeTo(800, 0.001));

      await p.setDebtSettled('d1', true, record: true);
      expect(p.totalOwedToYou, 0);
      expect(p.incomes.where((i) => i.title == 'Repaid by Ravi'), hasLength(1));

      await p.setDebtSettled('d1', false);
      expect(p.incomes.where((i) => i.title == 'Repaid by Ravi'), isEmpty);
      expect(p.totalOwedToYou, closeTo(800, 0.001));
    });
  });
}
