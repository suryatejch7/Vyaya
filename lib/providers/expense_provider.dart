import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/expense_models.dart';
import '../models/recurring_entry.dart';
import '../models/debt_entry.dart';
import '../models/user_settings.dart';
import '../services/local_store.dart';
import 'managers/expense_data_manager.dart';
import 'managers/income_data_manager.dart';
import 'managers/budget_manager.dart';
import 'managers/account_manager.dart';
import 'managers/notification_manager.dart';

enum FilterPeriod {
  weekly,
  monthly,
  yearly,
  allTime,
  custom,
}

class ExpenseProvider extends ChangeNotifier {
  final ExpenseDataManager _expenseManager = ExpenseDataManager();
  final IncomeDataManager _incomeManager = IncomeDataManager();
  final BudgetManager _budgetManager = BudgetManager();
  final AccountManager _accountManager = AccountManager();
  final NotificationManager _notificationManager = NotificationManager();

  final List<ExpenseCategory> _customCategories = [];
  String _searchQuery = '';

  int _userId = 0;
  String _userName = '';
  String _currency = '₹';

  bool _isLoading = false;
  bool _isInitialized = false;

  List<Expense> get expenses => _expenseManager.expenses;
  List<Income> get incomes => _incomeManager.incomes;
  List<ExpenseCategory> get customCategories => _customCategories;
  List<BankAccount> get accounts => _accountManager.accounts;
  int get userId => _userId;
  String get userName => _userName;
  double get monthlyBudget => _budgetManager.monthlyBudget;
  String get currency => _currency;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  bool get isInitialized => _isInitialized;

  BankAccount? get defaultAccount => _accountManager.defaultAccount;

  List<ExpenseCategory> get categories => _customCategories;

  Future<void> initializeWithUser(
      int userId, String userName, UserSettings userSettings) async {
    _userId = userId;
    _userName = userName;
    _currency = userSettings.currency;

    _budgetManager.initialize(
        userSettings.monthlyBudget, userSettings.categoryBudgets);
    _customCategories.clear();
    _customCategories.addAll(userSettings.customCategories);
    _accountManager.initialize(userSettings.accounts);

    await _expenseManager.loadExpenses(userId);
    _isInitialized = true;
    notifyListeners();

    await loadIncomes();

    // Recurring entries + month-end savings need expenses/incomes loaded.
    await _loadRecurring();
    await _loadDebts();
    await _clearDanglingAccountIds();
    await runAutomations();

    await _notificationManager
        .schedulePeriodicNotifications(_expenseManager.expenses);
  }

  void clearUserData() {
    _userId = 0;
    _userName = '';
    _currency = '₹';
    _budgetManager.clear();
    _customCategories.clear();
    _accountManager.clear();
    _expenseManager.clear();
    _incomeManager.clear();
    _recurring.clear();
    _debts.clear();
    _viewMonth = DateTime(DateTime.now().year, DateTime.now().month);
    _searchQuery = '';
    _isInitialized = false;
    notifyListeners();
  }

  void _refreshCalculations() {
    notifyListeners();
  }

  Future<void> forceRefresh() async {
    if (_userId == 0) return;

    try {
      _isLoading = true;
      notifyListeners();

      await _expenseManager.loadExpenses(_userId);

      await loadIncomes();

      final userSettings =
          await LocalStore.getUserSettings(userId: _userId);
      _budgetManager.initialize(
          userSettings.monthlyBudget, userSettings.categoryBudgets);
      _currency = userSettings.currency;
      _customCategories.clear();
      _customCategories.addAll(userSettings.customCategories);
      _accountManager.initialize(userSettings.accounts);

      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ==================== SEARCH & FILTERING ====================

  List<Expense> get filteredExpenses {
    if (_searchQuery.isEmpty) return _expenseManager.expenses;

    return _expenseManager.expenses.where((expense) {
      final query = _searchQuery.toLowerCase();
      return expense.description.toLowerCase().contains(query) ||
          (expense.payee?.toLowerCase().contains(query) ?? false) ||
          expense.amount.toString().contains(query) ||
          expense.amount.toStringAsFixed(0).contains(query) ||
          (expense.notes?.toLowerCase().contains(query) ?? false) ||
          expense.category.toLowerCase().contains(query);
    }).toList();
  }

  List<Income> get filteredIncomes {
    if (_searchQuery.isEmpty) return _incomeManager.incomes;

    return _incomeManager.incomes.where((income) {
      final query = _searchQuery.toLowerCase();
      return income.title.toLowerCase().contains(query) ||
          income.source.toLowerCase().contains(query) ||
          income.amount.toString().contains(query) ||
          income.amount.toStringAsFixed(0).contains(query) ||
          (income.notes?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch({bool notify = true}) {
    _searchQuery = '';
    if (notify) notifyListeners();
  }

  double get totalExpense {
    return _expenseManager.expenses
        .fold(0, (sum, expense) => sum + expense.amount);
  }

  double get totalIncome {
    return _incomeManager.incomes
        .fold(0.0, (sum, income) => sum + income.amount);
  }

  double get netBalance => totalIncome - totalExpense;

  /// Maps an expense's category name to the bucket it's shown under:
  /// itself if the category still exists, otherwise "Other" (e.g. expenses
  /// kept as-is after their category was deleted).
  String categoryBucket(String name) =>
      _customCategories.any((c) => c.name == name) ? name : 'Other';

  Map<String, double> get categoryTotals {
    Map<String, double> totals = {};
    for (var expense in _expenseManager.expenses) {
      final key = categoryBucket(expense.category);
      totals[key] = (totals[key] ?? 0) + expense.amount;
    }
    return totals;
  }

  // Income-based tracking (the monthly budget was removed from the UI).
  double get currentMonthLeft =>
      totalIncomeThisMonth - currentMonthTotalExpense;
  bool get isOverspent => currentMonthLeft < 0;
  double get overspentBy => currentMonthLeft < 0 ? -currentMonthLeft : 0;

  bool get isOverBudget =>
      _budgetManager.isOverBudget(currentMonthTotalExpense);
  double get budgetExcess =>
      _budgetManager.budgetExcess(currentMonthTotalExpense);
  double get budgetUsed => currentMonthTotalExpense;
  double get budgetRemaining =>
      _budgetManager.budgetRemaining(currentMonthTotalExpense);
  double get budgetUsagePercentage =>
      _budgetManager.budgetUsagePercentage(currentMonthTotalExpense);

  List<Expense> get currentMonthExpenses {
    final now = DateTime.now();
    return _expenseManager.expenses.where((expense) {
      return expense.date.year == now.year &&
          expense.date.month == now.month;
    }).toList();
  }

  double get currentMonthTotalExpense {
    return currentMonthExpenses.fold(0, (sum, expense) => sum + expense.amount);
  }

  Map<String, double> get currentMonthCategoryTotals {
    Map<String, double> totals = {};
    for (var expense in currentMonthExpenses) {
      final key = categoryBucket(expense.category);
      totals[key] = (totals[key] ?? 0) + expense.amount;
    }
    return totals;
  }

  List<Expense> getCurrentMonthExpensesByCategory(String category) {
    return currentMonthExpenses
        .where((expense) => categoryBucket(expense.category) == category)
        .toList();
  }

  double getCurrentMonthCategoryExpenses(String category) {
    return currentMonthExpenses
        .where((expense) => categoryBucket(expense.category) == category)
        .fold(0.0, (sum, expense) => sum + expense.amount);
  }

  List<Expense> getExpensesByPeriodType(FilterPeriod period,
      {DateTime? customStart, DateTime? customEnd, String? accountId}) {
    final now = DateTime.now();

    List<Expense> baseExpenses = accountId != null
        ? _expenseManager.expenses
            .where((expense) => expense.accountId == accountId)
            .toList()
        : _expenseManager.expenses;

    switch (period) {
      case FilterPeriod.weekly:
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        return baseExpenses.where((expense) {
          return expense.date
                  .isAfter(weekStart.subtract(const Duration(days: 1))) &&
              expense.date.isBefore(now.add(const Duration(days: 1)));
        }).toList();

      case FilterPeriod.monthly:
        return baseExpenses.where((expense) {
          return expense.date.year == now.year &&
              expense.date.month == now.month;
        }).toList();

      case FilterPeriod.yearly:
        return baseExpenses.where((expense) {
          return expense.date.year == now.year;
        }).toList();

      case FilterPeriod.allTime:
        return List.from(baseExpenses);

      case FilterPeriod.custom:
        if (customStart == null || customEnd == null) {
          return List.from(baseExpenses);
        }
        return baseExpenses.where((expense) {
          return expense.date
                  .isAfter(customStart.subtract(const Duration(days: 1))) &&
              expense.date.isBefore(customEnd.add(const Duration(days: 1)));
        }).toList();
    }
  }

  double getTotalByPeriod(FilterPeriod period,
      {DateTime? customStart, DateTime? customEnd, String? accountId}) {
    return getExpensesByPeriodType(period,
            customStart: customStart,
            customEnd: customEnd,
            accountId: accountId)
        .fold(0, (sum, expense) => sum + expense.amount);
  }

  Map<String, double> getCategoryTotalsByPeriod(FilterPeriod period,
      {DateTime? customStart, DateTime? customEnd, String? accountId}) {
    final expenses = getExpensesByPeriodType(period,
        customStart: customStart,
        customEnd: customEnd,
        accountId: accountId);
    Map<String, double> totals = {};
    for (var expense in expenses) {
      final key = categoryBucket(expense.category);
      totals[key] = (totals[key] ?? 0) + expense.amount;
    }
    return totals;
  }

  List<Expense> getExpensesByCategoryAndPeriod(
      String category, FilterPeriod period,
      {DateTime? customStart, DateTime? customEnd, String? accountId}) {
    return getExpensesByPeriodType(period,
            customStart: customStart,
            customEnd: customEnd,
            accountId: accountId)
        .where((expense) => categoryBucket(expense.category) == category)
        .toList();
  }

  Future<void> addExpense(Expense expense) async {
    try {
      await _expenseManager.addExpense(expense, _userId);
      await _resyncSavings();

      await _notificationManager.triggerExpenseNotifications(
        expense: expense,
        allExpenses: _expenseManager.expenses,
        monthlyIncome: totalIncomeThisMonth,
        categoryBudget: getCategoryBudget(expense.category),
        categorySpent: getCategoryExpenses(expense.category),
        isFirstExpense: _expenseManager.expenses.length == 1,
      );

      notifyListeners();
    } catch (e) {
      throw Exception('Failed to add expense: $e');
    }
  }

  Future<void> updateExpense(Expense expense) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _expenseManager.updateExpense(expense, _userId);
      await _resyncSavings();
      _refreshCalculations();
    } catch (e) {
      throw Exception('Failed to update expense: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteExpense(String expenseId) async {
    try {
      _isLoading = true;
      notifyListeners();
      // Deleting a month's Saved entry yourself means "not for this month":
      // remember it so it isn't recreated.
      final target =
          _expenseManager.expenses.where((e) => e.id == expenseId).firstOrNull;
      final savedMonth = target == null ? null : _savedMonthOf(target);
      if (savedMonth != null) {
        await _setSkippedSavingsMonths(_skippedSavingsMonths..add(savedMonth));
      }
      await _expenseManager.deleteExpense(expenseId, _userId);
      await _resyncSavings();
      _refreshCalculations();
    } catch (e) {
      throw Exception('Failed to delete expense: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> reloadExpenses() async {
    if (_userId == 0) return;

    try {
      _isLoading = true;
      notifyListeners();

      await _expenseManager.reloadExpenses(_userId);
      await loadIncomes();

      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addIncome(Income income) async {
    try {
      await _incomeManager.addIncome(income, _userId);
      await _resyncSavings();
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to add income: $e');
    }
  }

  Future<void> updateIncome(Income income) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _incomeManager.updateIncome(income, _userId);
      await _resyncSavings();
      _refreshCalculations();
    } catch (e) {
      throw Exception('Failed to update income: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteIncome(String incomeId) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _incomeManager.deleteIncome(incomeId, _userId);
      await _resyncSavings();
      _refreshCalculations();
    } catch (e) {
      throw Exception('Failed to delete income: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  double get totalIncomeThisMonth {
    final now = DateTime.now();
    return _incomeManager.incomes
        .where((i) => i.date.year == now.year && i.date.month == now.month)
        .fold(0.0, (sum, i) => sum + i.amount);
  }

  double getTotalIncomeForAccount(String accountId) {
    return _incomeManager.incomes
        .where((i) => i.accountId == accountId)
        .fold(0.0, (sum, i) => sum + i.amount);
  }

  List<Income> getIncomesByPeriod(FilterPeriod period,
      {DateTime? customStart, DateTime? customEnd, String? accountId}) {
    final now = DateTime.now();
    List<Income> filtered = accountId != null
        ? _incomeManager.incomes
            .where((i) => i.accountId == accountId)
            .toList()
        : _incomeManager.incomes;

    switch (period) {
      case FilterPeriod.weekly:
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        return filtered
            .where((i) => i.date
                .isAfter(weekStart.subtract(const Duration(days: 1))))
            .toList();
      case FilterPeriod.monthly:
        return filtered
            .where(
                (i) => i.date.year == now.year && i.date.month == now.month)
            .toList();
      case FilterPeriod.yearly:
        return filtered.where((i) => i.date.year == now.year).toList();
      case FilterPeriod.allTime:
        return filtered;
      case FilterPeriod.custom:
        if (customStart != null && customEnd != null) {
          return filtered
              .where((i) =>
                  i.date.isAfter(
                      customStart.subtract(const Duration(days: 1))) &&
                  i.date
                      .isBefore(customEnd.add(const Duration(days: 1))))
              .toList();
        }
        return filtered;
    }
  }

  Future<void> loadIncomes() async {
    await _incomeManager.loadIncomes(_userId);
    notifyListeners();
  }

  Future<void> updateMonthlyBudget(double budget) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _budgetManager.updateMonthlyBudget(budget, _userId);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to update budget: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  double getCategoryBudget(String categoryName) {
    return _budgetManager.getCategoryBudget(categoryName, _customCategories);
  }

  Future<void> setCategoryBudget(String categoryName, double budget) async {
    try {
      await _budgetManager.setCategoryBudget(
          categoryName, budget, _customCategories, _userId);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to update category budget: $e');
    }
  }

  double getCustomCategoryBudget(String categoryId) {
    return _budgetManager.getCustomCategoryBudget(categoryId);
  }

  double getCustomCategoryExpenses(String categoryId) {
    final category = _customCategories.firstWhere(
      (cat) => cat.id == categoryId,
      orElse: () => ExpenseCategory(
        id: categoryId,
        name: 'Unknown Category',
        icon: '📦',
        color: Colors.grey,
      ),
    );
    return getCategoryExpenses(category.name);
  }

  Future<void> setCustomCategoryBudget(
      String categoryId, double budget) async {
    try {
      await _budgetManager.setCustomCategoryBudget(
          categoryId, budget, _userId);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to update category budget: $e');
    }
  }

  bool isCategoryOverBudget(String category) {
    return _budgetManager.isCategoryOverBudget(
        category, getCurrentMonthCategoryExpenses(category), _customCategories);
  }

  double getCategoryBudgetExcess(String category) {
    return _budgetManager.getCategoryBudgetExcess(
        category, getCurrentMonthCategoryExpenses(category), _customCategories);
  }

  Future<void> addCustomCategory(ExpenseCategory category) async {
    try {
      _customCategories.add(category);
      await LocalStore.saveCustomCategories(_customCategories,
          userId: _userId);
      notifyListeners();
    } catch (e) {
      _customCategories.removeWhere((cat) => cat.id == category.id);
      throw Exception('Failed to add category: $e');
    }
  }

  /// Edits a category. A rename moves every expense and recurring entry to
  /// the new name (expenses store the category by name).
  Future<void> updateCategory(String id,
      {required String name, required String icon, required Color color}) async {
    final idx = _customCategories.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final old = _customCategories[idx];
    final newName = name.trim();
    if (newName.isEmpty) throw ArgumentError('Name can\'t be empty');
    if (newName.toLowerCase() != old.name.toLowerCase() &&
        _customCategories.any((c) =>
            c.id != id && c.name.toLowerCase() == newName.toLowerCase())) {
      throw ArgumentError('A category called "$newName" already exists');
    }
    final renamed = newName != old.name;
    final snapshot = List<ExpenseCategory>.from(_customCategories);
    try {
      _customCategories[idx] = ExpenseCategory(
        id: old.id,
        name: newName,
        icon: icon,
        color: color,
        isDefault: old.isDefault,
      );
      await LocalStore.saveCustomCategories(_customCategories,
          userId: _userId);
      if (renamed) {
        await LocalStore.reassignExpenseCategories({old.name: newName},
            userId: _userId);
        var recurringChanged = false;
        for (var i = 0; i < _recurring.length; i++) {
          if (_recurring[i].category == old.name) {
            _recurring[i] = _recurring[i].copyWith(category: newName);
            recurringChanged = true;
          }
        }
        if (recurringChanged) await _saveRecurring();
        await reloadExpenses(); // refresh lists, totals and analytics
      }
      notifyListeners();
    } catch (e) {
      _customCategories
        ..clear()
        ..addAll(snapshot);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeCustomCategory(String categoryId) async {
    try {
      _customCategories.removeWhere((cat) => cat.id == categoryId);
      await LocalStore.saveCustomCategories(_customCategories,
          userId: _userId);
      notifyListeners();
    } catch (e) {
      if (_customCategories.every((cat) => cat.id != categoryId)) {
        _customCategories.add(ExpenseCategory(
          id: categoryId,
          name: 'Restored Category',
          icon: '📦',
          color: Colors.grey,
        ));
      }
      throw Exception('Failed to remove category: $e');
    }
  }

  /// Expense counts (from full storage, not just the loaded page) for the
  /// given category names. Names with no expenses are omitted.
  Future<Map<String, int>> getExpenseCountsForCategories(
      Iterable<String> names) async {
    final all =
        await LocalStore.getExpenseCountsByCategory(userId: _userId);
    return {
      for (final n in names)
        if ((all[n] ?? 0) > 0) n: all[n]!,
    };
  }

  /// Removes several categories (custom or default) in a single save.
  /// [reassign] maps a deleted category's name -> target category name; those
  /// expenses are moved before the categories are removed.
  Future<void> removeCustomCategories(Set<String> categoryIds,
      {Map<String, String> reassign = const {}}) async {
    if (categoryIds.isEmpty) return;
    final snapshot = List<ExpenseCategory>.from(_customCategories);
    try {
      if (reassign.isNotEmpty) {
        await LocalStore.reassignExpenseCategories(reassign,
            userId: _userId);
      }
      _customCategories.removeWhere((cat) => categoryIds.contains(cat.id));
      await LocalStore.saveCustomCategories(_customCategories,
          userId: _userId);
      if (reassign.isNotEmpty) {
        await reloadExpenses(); // refresh in-memory lists/analytics
      }
      notifyListeners();
    } catch (e) {
      _customCategories
        ..clear()
        ..addAll(snapshot);
      notifyListeners();
      throw Exception('Failed to remove categories: $e');
    }
  }

  // ==================== HOME SCREEN MONTH PICKER ====================

  DateTime _viewMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime get viewMonth => _viewMonth;

  bool get isViewingCurrentMonth {
    final now = DateTime.now();
    return _viewMonth.year == now.year && _viewMonth.month == now.month;
  }

  void previousViewMonth() {
    _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1);
    notifyListeners();
  }

  void nextViewMonth() {
    if (isViewingCurrentMonth) return; // no browsing into the future
    _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1);
    notifyListeners();
  }

  bool _inViewMonth(DateTime d) =>
      d.year == _viewMonth.year && d.month == _viewMonth.month;

  List<Expense> get viewMonthExpenses =>
      _expenseManager.expenses.where((e) => _inViewMonth(e.date)).toList();

  List<Income> get viewMonthIncomes =>
      _incomeManager.incomes.where((i) => _inViewMonth(i.date)).toList();

  double get viewMonthTotalExpense =>
      viewMonthExpenses.fold(0.0, (sum, e) => sum + e.amount);

  double get viewMonthIncome =>
      viewMonthIncomes.fold(0.0, (sum, i) => sum + i.amount);

  double get viewMonthLeft => viewMonthIncome - viewMonthTotalExpense;
  bool get viewMonthOverspent => viewMonthLeft < 0;
  double get viewMonthOverspentBy => viewMonthLeft < 0 ? -viewMonthLeft : 0;

  Map<String, double> get viewMonthCategoryTotals {
    final totals = <String, double>{};
    for (final e in viewMonthExpenses) {
      final key = categoryBucket(e.category);
      totals[key] = (totals[key] ?? 0) + e.amount;
    }
    return totals;
  }

  // ==================== UNDO (re-add deleted items) ====================

  Future<void> restoreExpenses(List<Expense> expenses) async {
    final skipped = _skippedSavingsMonths;
    var skipChanged = false;
    for (final e in expenses) {
      final savedMonth = _savedMonthOf(e);
      if (savedMonth != null) skipChanged |= skipped.remove(savedMonth);
      await _expenseManager.addExpense(e, _userId);
    }
    if (skipChanged) await _setSkippedSavingsMonths(skipped);
    await _resyncSavings();
    notifyListeners();
  }

  Future<void> restoreIncomes(List<Income> incomes) async {
    for (final i in incomes) {
      await _incomeManager.addIncome(i, _userId);
    }
    await _resyncSavings();
    notifyListeners();
  }

  // ==================== AUTOMATIONS ====================

  bool _automationsRunning = false;

  /// Creates due recurring entries, then moves finished months' leftovers
  /// into "Saved". Runs on app start/restore and when the app resumes.
  Future<void> runAutomations() async {
    if (_userId == 0 || _automationsRunning) return;
    _automationsRunning = true;
    try {
      await _processRecurring(); // first: may add entries to past months
      await _processMonthEndSavings();
    } catch (e) {
      debugPrint('Automations failed: $e');
    } finally {
      _automationsRunning = false;
      notifyListeners();
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _monthKey(DateTime m) =>
      '${m.year}-${m.month.toString().padLeft(2, '0')}';
  static DateTime? _parseMonthKey(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return (y == null || m == null) ? null : DateTime(y, m);
  }

  // ==================== RECURRING ENTRIES ====================

  final List<RecurringEntry> _recurring = [];
  List<RecurringEntry> get recurringEntries => List.unmodifiable(_recurring);

  Future<void> _loadRecurring() async {
    final raw =
        await LocalStore.getJsonList('recurring', userId: _userId);
    _recurring
      ..clear()
      ..addAll(raw.map(RecurringEntry.fromJson));
  }

  Future<void> _saveRecurring() => LocalStore.saveJsonList(
      'recurring', _recurring.map((r) => r.toJson()).toList(),
      userId: _userId);

  Future<void> addRecurring(RecurringEntry entry) async {
    _recurring.add(entry);
    await _saveRecurring();
    await _processRecurring(); // creates it now if already due
    notifyListeners();
  }

  Future<void> updateRecurring(RecurringEntry entry) async {
    final i = _recurring.indexWhere((r) => r.id == entry.id);
    if (i == -1) return;
    _recurring[i] = entry;
    await _saveRecurring();
    await _processRecurring();
    notifyListeners();
  }

  Future<void> deleteRecurring(String id) async {
    _recurring.removeWhere((r) => r.id == id);
    await _saveRecurring();
    notifyListeners();
  }

  /// Pausing keeps the schedule; resuming skips the missed months instead
  /// of back-filling them.
  Future<void> setRecurringActive(String id, bool active) async {
    final i = _recurring.indexWhere((r) => r.id == id);
    if (i == -1) return;
    var r = _recurring[i].copyWith(active: active);
    if (active) {
      final today = _dateOnly(DateTime.now());
      if (r.nextDue.isBefore(today)) {
        r = r.copyWith(nextDue: r.occurrenceOnOrAfter(today));
      }
    }
    _recurring[i] = r;
    await _saveRecurring();
    await _processRecurring();
    notifyListeners();
  }

  Future<void> _processRecurring() async {
    final today = _dateOnly(DateTime.now());
    var changed = false;
    for (var i = 0; i < _recurring.length; i++) {
      var r = _recurring[i];
      if (!r.active) continue;
      var guard = 0; // catch-up cap (104 weeks / 24 months / 3 years)
      while (!r.nextDue.isAfter(today) && guard < r.catchUpLimit) {
        await _createFromRecurring(r, r.nextDue);
        r = r.copyWith(nextDue: r.nextAfter(r.nextDue));
        changed = true;
        guard++;
      }
      _recurring[i] = r;
    }
    if (changed) await _saveRecurring();
  }

  Future<void> _createFromRecurring(RecurringEntry r, DateTime due) async {
    final now = DateTime.now();
    final accountId = r.accountId ?? defaultAccount?.id;
    if (r.isIncome) {
      await _incomeManager.addIncome(
        Income(
          amount: r.amount,
          title: r.title,
          source: r.source,
          date: due,
          notes: r.notes,
          accountId: accountId,
          createdAt: now,
          updatedAt: now,
        ),
        _userId,
      );
    } else {
      await _expenseManager.addExpense(
        Expense(
          amount: r.amount,
          description: r.title,
          category: r.category,
          date: due,
          paymentApp: 'Recurring',
          notes: r.notes,
          accountId: accountId,
          createdAt: now,
          updatedAt: now,
        ),
        _userId,
      );
    }
  }

  // ==================== MONTH-END SAVINGS ====================

  static const String savedCategoryName = 'Saved';

  /// Tag stored in Expense.transactionId to mark the automatic Saved entry
  /// of a month, e.g. "auto-saved-2026-09".
  static const String _autoSavedPrefix = 'auto-saved-';

  static bool _isAutoSaved(Expense e) =>
      e.transactionId?.startsWith(_autoSavedPrefix) ?? false;

  /// True for the automatic month-end "Saved" entry. It's stored as an
  /// expense so the month balances, but it isn't spending, so analytics
  /// leaves it out.
  static bool isAutoSavedEntry(Expense e) => _isAutoSaved(e);

  bool _savingsRunning = false;

  /// Month-end savings on/off (Settings → Money). On by default.
  bool get monthEndSavingsEnabled =>
      LocalStore.getMeta('savings_enabled', userId: _userId) != '0';

  /// Months whose Saved entry you deleted yourself; they aren't recreated.
  Set<String> get _skippedSavingsMonths {
    final raw = LocalStore.getMeta('savings_skip', userId: _userId);
    if (raw == null || raw.isEmpty) return {};
    return raw.split(',').where((s) => s.isNotEmpty).toSet();
  }

  Future<void> _setSkippedSavingsMonths(Set<String> months) =>
      LocalStore.setMeta('savings_skip', (months.toList()..sort()).join(','),
          userId: _userId);

  /// Month key ("2026-09") of an automatic Saved entry.
  static String? _savedMonthOf(Expense e) => _isAutoSaved(e)
      ? e.transactionId!.substring(_autoSavedPrefix.length)
      : null;

  /// Turns month-end savings on or off. Turning off can also delete the
  /// Saved entries already made. Turning back on starts from this month
  /// (earlier months aren't back-filled).
  Future<void> setMonthEndSavings(bool on, {bool removeExisting = false}) async {
    await LocalStore.setMeta('savings_enabled', on ? '1' : '0',
        userId: _userId);
    if (on) {
      final now = DateTime.now();
      await LocalStore.setMeta(
          'savings_from', _monthKey(DateTime(now.year, now.month)),
          userId: _userId);
    } else if (removeExisting) {
      for (final e in _expenseManager.expenses.where(_isAutoSaved).toList()) {
        if (e.id != null) await _expenseManager.deleteExpense(e.id!, _userId);
      }
    }
    notifyListeners();
  }

  /// Keeps every closed month's "Saved" entry equal to that month's
  /// leftover (income - spent, excluding the Saved entry itself). Creates,
  /// updates or removes it as needed, so late edits to a past month are
  /// reflected automatically. Months before this feature started are left
  /// alone (no back-filling).
  Future<void> _processMonthEndSavings() async {
    if (_userId == 0 || _savingsRunning || !monthEndSavingsEnabled) return;
    _savingsRunning = true;
    try {
      final now = DateTime.now();
      final thisMonth = DateTime(now.year, now.month);

      var fromKey =
          LocalStore.getMeta('savings_from', userId: _userId);
      if (fromKey == null) {
        // Migrate from the earlier one-shot marker if present.
        final legacy =
            LocalStore.getMeta('savings_through', userId: _userId);
        final legacyMonth = legacy == null ? null : _parseMonthKey(legacy);
        final from = legacyMonth == null
            ? thisMonth
            : DateTime(legacyMonth.year, legacyMonth.month + 1);
        fromKey = _monthKey(from);
        await LocalStore.setMeta('savings_from', fromKey,
            userId: _userId);
      }

      final from = _parseMonthKey(fromKey);
      if (from == null) return;
      final skipped = _skippedSavingsMonths;
      for (var m = from;
          m.isBefore(thisMonth);
          m = DateTime(m.year, m.month + 1)) {
        if (skipped.contains(_monthKey(m))) continue; // you deleted it
        await _reconcileSavingsFor(m);
      }
    } finally {
      _savingsRunning = false;
    }
  }

  Future<void> _reconcileSavingsFor(DateTime m) async {
    final now = DateTime.now();
    final tag = '$_autoSavedPrefix${_monthKey(m)}';
    bool inMonth(DateTime d) => d.year == m.year && d.month == m.month;

    final income = _incomeManager.incomes
        .where((i) => inMonth(i.date))
        .fold(0.0, (sum, i) => sum + i.amount);
    final spent = _expenseManager.expenses
        .where((e) => inMonth(e.date) && !_isAutoSaved(e))
        .fold(0.0, (sum, e) => sum + e.amount);
    final left = double.parse((income - spent).toStringAsFixed(2));

    final autoEntries =
        _expenseManager.expenses.where((e) => e.transactionId == tag).toList();
    // Safety: never keep more than one Saved entry per month.
    for (final extra in autoEntries.skip(1)) {
      if (extra.id != null) {
        await _expenseManager.deleteExpense(extra.id!, _userId);
      }
    }
    final existing = autoEntries.isEmpty ? null : autoEntries.first;

    if (left > 0) {
      await _ensureSavedCategory();
      if (existing == null) {
        await _expenseManager.addExpense(
          Expense(
            amount: left,
            description: 'Saved from ${DateFormat('MMMM yyyy').format(m)}',
            category: savedCategoryName,
            date: DateTime(m.year, m.month + 1, 0), // last day of month
            paymentApp: 'Auto',
            transactionId: tag,
            notes: 'Leftover (income − spent), kept up to date automatically',
            accountId: defaultAccount?.id,
            createdAt: now,
            updatedAt: now,
          ),
          _userId,
        );
      } else if ((existing.amount - left).abs() >= 0.005 ||
          existing.category != savedCategoryName) {
        await _expenseManager.updateExpense(
          existing.copyWith(
            amount: left,
            category: savedCategoryName,
            updatedAt: now,
          ),
          _userId,
        );
      }
    } else if (existing?.id != null) {
      // Month no longer has a leftover (e.g. a late expense was added).
      await _expenseManager.deleteExpense(existing!.id!, _userId);
    }
  }

  /// Re-checks closed months after any add/edit/delete.
  Future<void> _resyncSavings() async {
    try {
      await _processMonthEndSavings();
    } catch (e) {
      debugPrint('Savings resync failed: $e');
    }
  }

  Future<void> _ensureSavedCategory() async {
    if (_customCategories.any((c) => c.name == savedCategoryName)) return;
    var id = 'saved';
    if (_customCategories.any((c) => c.id == id)) {
      id = 'saved_${DateTime.now().millisecondsSinceEpoch}';
    }
    await addCustomCategory(ExpenseCategory(
      id: id,
      name: savedCategoryName,
      icon: '💰',
      color: Colors.teal,
    ));
  }

  // ==================== LENT & BORROWED ====================

  final List<DebtEntry> _debts = [];
  List<DebtEntry> get debts {
    final list = List<DebtEntry>.from(_debts);
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Future<void> _loadDebts() async {
    final raw =
        await LocalStore.getJsonList('debts', userId: _userId);
    _debts
      ..clear()
      ..addAll(raw.map(DebtEntry.fromJson));
  }

  Future<void> _saveDebts() => LocalStore.saveJsonList(
      'debts', _debts.map((d) => d.toJson()).toList(),
      userId: _userId);

  Future<void> addDebt(DebtEntry entry) async {
    _debts.add(entry);
    await _saveDebts();
    notifyListeners();
  }

  Future<void> updateDebt(DebtEntry entry) async {
    final i = _debts.indexWhere((d) => d.id == entry.id);
    if (i == -1) return;
    _debts[i] = entry;
    await _saveDebts();
    notifyListeners();
  }

  Future<void> deleteDebt(String id) async {
    _debts.removeWhere((d) => d.id == id);
    await _saveDebts();
    notifyListeners();
  }

  /// Settles or reopens an entry. With [record], settling also logs the
  /// money that changed hands: income when someone repays you, an expense
  /// when you repay them. Reopening removes that recorded entry again.
  Future<void> setDebtSettled(String id, bool settled,
      {bool record = false}) async {
    final i = _debts.indexWhere((d) => d.id == id);
    if (i == -1) return;
    final d = _debts[i];
    if (settled) {
      String? entryId;
      if (record) entryId = await _recordSettlement(d);
      _debts[i] = d.copyWith(
          settled: true, settledAt: DateTime.now(), settlementEntryId: entryId);
    } else {
      final entry = d.settlementEntryId;
      if (entry != null) {
        try {
          if (d.isLent) {
            await deleteIncome(entry);
          } else {
            await deleteExpense(entry);
          }
        } catch (e) {
          debugPrint('Removing settlement entry failed: $e');
        }
      }
      _debts[i] = d.copyWith(
          settled: false, clearSettledAt: true, clearSettlement: true);
    }
    await _saveDebts();
    notifyListeners();
  }

  /// Logs a settlement and returns the new income/expense id.
  Future<String?> _recordSettlement(DebtEntry d) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final note = 'Settled from Lent & Borrowed'
        '${d.note == null || d.note!.isEmpty ? '' : ' · ${d.note}'}';
    if (d.isLent) {
      await addIncome(Income(
        amount: d.amount,
        title: 'Repaid by ${d.person}',
        source: d.person,
        date: today,
        notes: note,
        accountId: defaultAccount?.id,
        createdAt: now,
        updatedAt: now,
      ));
      for (final inc in _incomeManager.incomes) {
        if (inc.createdAt == now && (inc.amount - d.amount).abs() < 0.009) {
          return inc.id;
        }
      }
      return null;
    }
    final tag = 'debt-${d.id}-${now.millisecondsSinceEpoch}';
    await addExpense(Expense(
      amount: d.amount,
      description: 'Repaid ${d.person}',
      category: categoryBucket('Other'),
      date: today,
      paymentApp: 'Lent & Borrowed',
      transactionId: tag,
      notes: note,
      accountId: defaultAccount?.id,
      createdAt: now,
      updatedAt: now,
    ));
    for (final e in _expenseManager.expenses) {
      if (e.transactionId == tag) return e.id;
    }
    return null;
  }

  /// Open (unsettled) balance per person: + they owe you, - you owe them.
  Map<String, double> get debtBalances {
    final balances = <String, double>{};
    for (final d in _debts.where((d) => !d.settled)) {
      final name = d.person.trim();
      balances[name] = (balances[name] ?? 0) + d.signedAmount;
    }
    balances.removeWhere((_, v) => v.abs() < 0.005);
    return balances;
  }

  double get totalOwedToYou => debtBalances.values
      .where((v) => v > 0)
      .fold(0.0, (sum, v) => sum + v);

  double get totalYouOwe => debtBalances.values
      .where((v) => v < 0)
      .fold(0.0, (sum, v) => sum - v);

  List<String> get debtPeople {
    final seen = <String>{};
    return debts.map((d) => d.person.trim()).where(seen.add).toList();
  }

  BankAccount? getAccountById(String accountId) =>
      _accountManager.getAccountById(accountId);

  String getAccountName(String? accountId) =>
      _accountManager.getAccountName(accountId);

  Future<void> addAccount(BankAccount account) async {
    try {
      await _accountManager.addAccount(account, _userId);
      notifyListeners();
    } catch (e) {
      _accountManager.accounts.removeWhere((acc) => acc.id == account.id);
      throw Exception('Failed to add account: $e');
    }
  }

  /// Older versions deleted accounts without moving their entries, leaving
  /// ids that match no account (blank name, and account pickers can't show
  /// them). Clears those links once at startup.
  Future<void> _clearDanglingAccountIds() async {
    final valid = _accountManager.accounts.map((a) => a.id).toSet();
    if (valid.isEmpty) return; // nothing to compare against
    bool dangling(String? id) =>
        id != null && id.isNotEmpty && !valid.contains(id);
    final ids = <String>{
      for (final e in _expenseManager.expenses)
        if (dangling(e.accountId)) e.accountId!,
      for (final i in _incomeManager.incomes)
        if (dangling(i.accountId)) i.accountId!,
    };
    final recurringIdx = [
      for (var i = 0; i < _recurring.length; i++)
        if (dangling(_recurring[i].accountId)) i,
    ];
    if (ids.isEmpty && recurringIdx.isEmpty) return;
    try {
      for (final id in ids) {
        await LocalStore.reassignAccount(id, null, userId: _userId);
      }
      for (final i in recurringIdx) {
        _recurring[i] = RecurringEntry.fromJson(
            {..._recurring[i].toJson(), 'account_id': null});
      }
      if (recurringIdx.isNotEmpty) await _saveRecurring();
      if (ids.isNotEmpty) {
        await _expenseManager.reloadExpenses(_userId);
        await _incomeManager.loadIncomes(_userId);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Clearing old account links failed: $e');
    }
  }

  /// How many expenses, incomes and recurring entries use this account.
  int accountUsageCount(String accountId) =>
      _expenseManager.expenses.where((e) => e.accountId == accountId).length +
      _incomeManager.incomes.where((i) => i.accountId == accountId).length +
      _recurring.where((r) => r.accountId == accountId).length;

  /// Deletes an account. Anything that used it moves to [moveTo], or is left
  /// with no account when [moveTo] is null, so nothing keeps pointing at an
  /// account that no longer exists.
  Future<void> removeAccount(String accountId, {String? moveTo}) async {
    try {
      final used = accountUsageCount(accountId) > 0;
      if (used) {
        await LocalStore.reassignAccount(accountId, moveTo,
            userId: _userId);
        var recurringChanged = false;
        for (var i = 0; i < _recurring.length; i++) {
          if (_recurring[i].accountId == accountId) {
            // Via JSON so a null target really clears the field.
            _recurring[i] = RecurringEntry.fromJson(
                {..._recurring[i].toJson(), 'account_id': moveTo});
            recurringChanged = true;
          }
        }
        if (recurringChanged) await _saveRecurring();
      }
      await _accountManager.removeAccount(accountId, _userId);
      if (used) await reloadExpenses(); // refresh in-memory lists
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to remove account: $e');
    }
  }

  /// Rename an account or change its type. Entries point at the account id,
  /// so nothing else has to change.
  Future<void> updateAccount(BankAccount account) async {
    await _accountManager.updateAccount(account, _userId);
    notifyListeners();
  }

  Future<void> setDefaultAccount(String accountId) async {
    try {
      await _accountManager.setDefaultAccount(accountId, _userId);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to set default account: $e');
    }
  }

  void updateLocalUserName(String newName) {
    if (newName.isNotEmpty && newName != _userName) {
      _userName = newName;
      notifyListeners();
    }
  }

  List<Expense> getExpensesByCategory(String category) {
    return _expenseManager.expenses
        .where((expense) => categoryBucket(expense.category) == category)
        .toList();
  }

  double getCategoryExpenses(String category) {
    return currentMonthExpenses
        .where((expense) => categoryBucket(expense.category) == category)
        .fold(0.0, (sum, expense) => sum + expense.amount);
  }
}
