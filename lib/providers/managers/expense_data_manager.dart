import '../../models/expense_models.dart';
import '../../services/local_store.dart';

/// In-memory list of the current user's expenses, kept in step with
/// [LocalStore]. Everything is on the device, so the whole list is loaded
/// at once (totals, analytics and search all work from it).
class ExpenseDataManager {
  final List<Expense> _expenses = [];

  List<Expense> get expenses => _expenses;

  /// Goes up on every change, so totals worked out from the list can be
  /// reused until it changes.
  int revision = 0;

  /// Newest expense date first; same date -> most recently logged first.
  static int byDateDesc(Expense a, Expense b) {
    final c = b.date.compareTo(a.date);
    return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
  }

  /// (Re)loads every expense from storage.
  Future<void> loadExpenses(int userId) async {
    final expenses = List<Expense>.from(
      await LocalStore.getExpenses(userId: userId),
    )..sort(byDateDesc);
    _expenses
      ..clear()
      ..addAll(expenses);
    revision++;
  }

  /// Same as [loadExpenses]; kept for callers that refresh after bulk edits.
  Future<void> reloadExpenses(int userId) => loadExpenses(userId);

  Future<void> addExpense(Expense expense, int userId) async {
    final expenseId = await LocalStore.addExpense(expense, userId);
    final expenseWithId = expense.copyWith(id: expenseId);
    if (!_expenses.any((e) => e.id == expenseId)) {
      // Put in its place (a back-dated expense lands among its date); the
      // list is already in order, so no full re-sort.
      _expenses.insert(_insertAt(expenseWithId), expenseWithId);
      revision++;
    }
  }

  /// First index whose expense sorts after [e] (binary search).
  int _insertAt(Expense e) {
    var lo = 0, hi = _expenses.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (byDateDesc(_expenses[mid], e) <= 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Adds several at once (undo of a big delete): one write, one sort.
  Future<void> addMany(List<Expense> items, int userId) async {
    if (items.isEmpty) return;
    final ids = await LocalStore.addExpenses(items, userId);
    for (var k = 0; k < items.length; k++) {
      _expenses.add(items[k].copyWith(id: ids[k]));
    }
    _expenses.sort(byDateDesc);
    revision++;
  }

  /// Deletes several at once: one pass over the list.
  Future<void> deleteMany(Set<String> ids, int userId) async {
    if (ids.isEmpty) return;
    await LocalStore.deleteExpenses(ids, userId);
    _expenses.removeWhere((e) => ids.contains(e.id));
    revision++;
  }

  Future<void> updateExpense(Expense expense, int userId) async {
    await LocalStore.updateExpense(expense, userId);
    final index = _expenses.indexWhere((e) => e.id == expense.id);
    if (index != -1) {
      _expenses[index] = expense;
      _expenses.sort(byDateDesc); // date may have been edited
      revision++;
    }
  }

  Future<void> deleteExpense(String expenseId, int userId) async {
    await LocalStore.deleteExpense(expenseId, userId);
    _expenses.removeWhere((expense) => expense.id == expenseId);
    revision++;
  }

  void clear() {
    _expenses.clear();
    revision++;
  }
}
