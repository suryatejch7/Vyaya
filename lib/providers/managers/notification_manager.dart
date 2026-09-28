import '../../models/expense_models.dart';
import '../../services/notification_service.dart';

class NotificationManager {
  Future<void> triggerExpenseNotifications({
    required Expense expense,
    required List<Expense> allExpenses,
    required double monthlyIncome,
    required double categoryBudget,
    required double categorySpent,
    required bool isFirstExpense,
  }) async {
    try {
      // Totals below are for the current month; an expense logged for an
      // earlier month can't push this month over anything.
      final now = DateTime.now();
      if (expense.date.year != now.year || expense.date.month != now.month) {
        return;
      }

      final monthlyExpenses = _getExpensesForMonth(allExpenses);
      final monthlySpent = monthlyExpenses.fold(
        0.0,
        (sum, e) => sum + e.amount,
      );
      // Alert only for the expense that crosses the line, not for every
      // expense after it (e.g. "Add all" on several detected payments).
      if (_crossed(monthlySpent, expense.amount, monthlyIncome)) {
        await NotificationService.checkIncomeExceeded(
          monthlySpent,
          monthlyIncome,
        );
      }

      if (categoryBudget > 0 &&
          _crossed(categorySpent, expense.amount, categoryBudget)) {
        await NotificationService.checkCategoryBudgetExceeded(
          expense.category,
          categorySpent,
          categoryBudget,
        );
      }
    } catch (e) {
      // Notifications are best-effort.
    }
  }

  Future<void> schedulePeriodicNotifications(List<Expense> allExpenses) async {
  }

  /// True when adding [amount] moved [totalAfter] from at/below [limit]
  /// to above it.
  bool _crossed(double totalAfter, double amount, double limit) =>
      limit > 0 && totalAfter > limit && totalAfter - amount <= limit;

  List<Expense> _getExpensesForMonth(List<Expense> expenses) {
    final now = DateTime.now();
    return expenses.where((expense) {
      return expense.date.year == now.year && expense.date.month == now.month;
    }).toList();
  }
}