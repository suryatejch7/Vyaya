import '../../models/expense_models.dart';
import '../../services/local_store.dart';

/// In-memory list of the current user's expenses, kept in step with
/// [LocalStore]. Everything is on the device, so the whole list is loaded
/// at once (totals, analytics and search all work from it).
class ExpenseDataManager {
  final List<Expense> _expenses = [];

  List<Expense> get expenses => _expenses;

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
  }

  /// Same as [loadExpenses]; kept for callers that refresh after bulk edits.
  Future<void> reloadExpenses(int userId) => loadExpenses(userId);

  Future<void> addExpense(Expense expense, int userId) async {
    final expenseId = await LocalStore.addExpense(expense, userId);
    final expenseWithId = expense.copyWith(id: expenseId);
    if (!_expenses.any((e) => e.id == expenseId)) {
      _expenses.add(expenseWithId);
      _expenses.sort(byDateDesc); // a back-dated expense lands in its place
    }
  }

  Future<void> updateExpense(Expense expense, int userId) async {
    await LocalStore.updateExpense(expense, userId);
    final index = _expenses.indexWhere((e) => e.id == expense.id);
    if (index != -1) {
      _expenses[index] = expense;
      _expenses.sort(byDateDesc); // date may have been edited
    }
  }

  Future<void> deleteExpense(String expenseId, int userId) async {
    await LocalStore.deleteExpense(expenseId, userId);
    _expenses.removeWhere((expense) => expense.id == expenseId);
  }

  void clear() => _expenses.clear();
}
