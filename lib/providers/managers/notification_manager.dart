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
      final monthlyExpenses = _getExpensesForMonth(allExpenses);
      final monthlySpent = monthlyExpenses.fold(
        0.0,
        (sum, e) => sum + e.amount,
      );
      await NotificationService.checkIncomeExceeded(
        monthlySpent,
        monthlyIncome,
      );

      if (categoryBudget > 0) {
        await NotificationService.checkCategoryBudgetExceeded(
          expense.category,
          categorySpent,
          categoryBudget,
        );
      }
    } catch (e) {
    }
  }

  Future<void> schedulePeriodicNotifications(List<Expense> allExpenses) async {
  }

  List<Expense> _getExpensesForMonth(List<Expense> expenses) {
    final now = DateTime.now();
    return expenses.where((expense) {
      return expense.date.year == now.year && expense.date.month == now.month;
    }).toList();
  }
}