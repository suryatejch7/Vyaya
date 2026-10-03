// On-device store: batch add/delete, ids, and values kept to this phone.
// Run: flutter test test/local_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expensetracker/models/expense_models.dart';
import 'package:expensetracker/services/local_store.dart';

Expense _e(double amount) => Expense(
      amount: amount,
      description: 'x',
      category: 'Food',
      date: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.initialize();
    await LocalStore.resetAllData();
  });

  test('batch add gives consecutive new ids after single adds', () async {
    final first = await LocalStore.addExpense(_e(1), 1);
    final ids = await LocalStore.addExpenses([_e(2), _e(3), _e(4)], 1);
    final next = await LocalStore.addExpense(_e(5), 1);
    final n = int.parse(first);
    expect(ids, ['${n + 1}', '${n + 2}', '${n + 3}']);
    expect(next, '${n + 4}');
    final all = await LocalStore.getExpenses(userId: 1);
    expect(all.map((e) => e.amount).toSet(), {1.0, 2.0, 3.0, 4.0, 5.0});
  });

  test('batch delete removes exactly those, and it reaches storage',
      () async {
    final ids = await LocalStore.addExpenses([_e(1), _e(2), _e(3)], 1);
    await LocalStore.deleteExpenses({ids[0], ids[2]}, 1);
    await LocalStore.flush();
    // Read back from the stored copy, not the in-memory one.
    LocalStore.discardPending();
    final all = await LocalStore.getExpenses(userId: 1);
    expect(all.map((e) => e.id), [ids[1]]);
  });

  test('income batch works the same', () async {
    final now = DateTime(2026, 9, 1);
    Income inc(double a) => Income(
        amount: a,
        title: 't',
        source: 's',
        date: now,
        createdAt: now,
        updatedAt: now);
    final ids = await LocalStore.addIncomes([inc(10), inc(20)], 1);
    await LocalStore.deleteIncomes({ids.first}, 1);
    final all = await LocalStore.getIncomes(userId: 1);
    expect(all.single.amount, 20);
  });

  test('values about this phone are not app data (not backed up)', () async {
    final id = LocalStore.installId();
    expect(id, isNotEmpty);
    expect(LocalStore.installId(), id); // stable
    await LocalStore.setDeviceValue('x', '1');
    expect(LocalStore.getDeviceValue('x'), '1');
    final prefs = await SharedPreferences.getInstance();
    // Backups copy only ls_* keys.
    expect(prefs.getKeys().where((k) => k.startsWith('device_')), isNotEmpty);
    expect(prefs.getKeys().where((k) => k.startsWith('ls_') && k.contains('install')),
        isEmpty);
  });
}
