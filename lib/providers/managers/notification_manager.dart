import '../../models/expense_models.dart';
import '../../services/notification_service.dart';
import '../../services/app_prefs.dart';
import '../../services/money_format.dart';

class NotificationManager {
  Future<void> triggerExpenseNotifications({
    required Expense expense,
    required List<Expense> allExpenses,
    required double monthlyIncome,
    required double categoryBudget,
    required double categorySpent,
    required bool isFirstExpense,
    // How much this change added (an edit from ₹500 to ₹5,000 adds 4,500).
    // Defaults to the whole amount, for a new expense.
    double? increase,
    // What it added to this month's total, when that differs from
    // [increase] (moving an expense to another category adds to that
    // category but nothing to the month).
    double? monthIncrease,
    // Large-payment alert only for payments you just made, not edits or
    // recurring entries.
    bool checkLargePayment = true,
  }) async {
    final added = increase ?? expense.amount;
    final monthAdded = monthIncrease ?? added;
    if (added <= 0 && monthAdded <= 0) return;
    try {
      // Optional large-payment alert: only for fresh payments (logged
      // today), not back-dated entries or imported history.
      final prefs = AppPrefs.instance;
      final limit = prefs.largePaymentAlert;
      final today = DateTime.now();
      bool sameDay(DateTime a, DateTime b) =>
          a.year == b.year && a.month == b.month && a.day == b.day;
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final fresh = sameDay(expense.date, today) ||
          // "Late night counts as yesterday": a payment at 1 AM is dated
          // yesterday but was just made.
          (prefs.lateNightIsYesterday &&
              sameDay(expense.date, yesterday) &&
              sameDay(expense.createdAt, today) &&
              expense.createdAt.hour < AppPrefs.lateNightCutoffHour);
      if (checkLargePayment &&
          limit != null &&
          expense.amount >= limit &&
          fresh) {
        await NotificationService.showLargePayment(
            expense.description, expense.amount);
      }

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
      if (_crossed(monthlySpent, monthAdded, monthlyIncome)) {
        await NotificationService.checkIncomeExceeded(
          monthlySpent,
          monthlyIncome,
        );
      }

      // Optional early warnings at 80%, so there's time to slow down.
      if (AppPrefs.instance.earlyWarnings &&
          AppPrefs.instance.notificationsOn) {
        if (monthlyIncome > 0 &&
            monthlySpent <= monthlyIncome &&
            _crossed(monthlySpent, monthAdded, monthlyIncome * 0.8)) {
          await NotificationService.showNearLimit(
            '80% of this month\'s income spent',
            '₹${formatAmount((monthlyIncome - monthlySpent), 0)} left for the rest of the month.',
          );
        }
        if (categoryBudget > 0 &&
            categorySpent <= categoryBudget &&
            _crossed(categorySpent, added, categoryBudget * 0.8)) {
          await NotificationService.showNearLimit(
            '${expense.category}: 80% of limit used',
            '₹${formatAmount((categoryBudget - categorySpent), 0)} left of your ₹${formatAmount(categoryBudget, 0)} ${expense.category} limit.',
          );
        }
      }

      if (categoryBudget > 0 &&
          _crossed(categorySpent, added, categoryBudget)) {
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