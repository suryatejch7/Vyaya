import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/expense_models.dart';
import '../models/recurring_entry.dart';
import '../models/debt_entry.dart';
import '../models/user_settings.dart';
import '../services/local_store.dart';
import '../services/app_prefs.dart';
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

  bool _isLoading = false;
  bool _isInitialized = false;

  List<Expense> get expenses => _expenseManager.expenses;
  List<Income> get incomes => _incomeManager.incomes;
  List<ExpenseCategory> get customCategories => _customCategories;
  List<BankAccount> get accounts => _accountManager.accounts;
  int get userId => _userId;
  String get userName => _userName;
  /// Always rupees: Vyaya is for India only (an old setting or backup
  /// with another symbol is ignored).
  String get currency => '₹';
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  bool get isInitialized => _isInitialized;

  BankAccount? get defaultAccount => _accountManager.defaultAccount;

  List<ExpenseCategory> get categories => _customCategories;

  Future<void> initializeWithUser(
      int userId, String userName, UserSettings userSettings) async {
    _userId = userId;
    _userName = userName;

    _budgetManager.initialize(userSettings.categoryBudgets);
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
      _budgetManager.initialize(userSettings.categoryBudgets);
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

  /// Expenses matching [query] (already trimmed). Doesn't store anything
  /// or notify, so typing in Search doesn't rebuild the rest of the app.
  List<Expense> searchExpenses(String query) {
    final q = query.toLowerCase();
    if (q.isEmpty) return _expenseManager.expenses;
    return _expenseManager.expenses.where((expense) {
      return expense.description.toLowerCase().contains(q) ||
          (expense.payee?.toLowerCase().contains(q) ?? false) ||
          expense.amount.toString().contains(q) ||
          expense.amount.toStringAsFixed(0).contains(q) ||
          (expense.notes?.toLowerCase().contains(q) ?? false) ||
          expense.category.toLowerCase().contains(q);
    }).toList();
  }

  List<Income> searchIncomes(String query) {
    final q = query.toLowerCase();
    if (q.isEmpty) return _incomeManager.incomes;
    return _incomeManager.incomes.where((income) {
      return income.title.toLowerCase().contains(q) ||
          income.source.toLowerCase().contains(q) ||
          income.amount.toString().contains(q) ||
          income.amount.toStringAsFixed(0).contains(q) ||
          (income.notes?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  void setSearchQuery(String query) {
    // Keyboards add a space after a tapped suggestion ("swiggy "), which
    // matched nothing; extra spaces are ignored.
    _searchQuery = query.trim().replaceAll(RegExp(r'\s+'), ' ');
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

  /// [categoryBucket] for many expenses: looks names up in a set made once.
  String Function(String) _bucketer() {
    final names = {for (final c in _customCategories) c.name};
    return (name) => names.contains(name) ? name : 'Other';
  }

  // This month's spending per category, worked out once and reused until
  // an expense, a category name or the month changes (budget cards ask for
  // every category on every rebuild).
  Map<String, double>? _monthByCategory;
  Object? _monthByCategoryKey;

  Map<String, double> _currentMonthByCategory() {
    final now = DateTime.now();
    final key = (
      _expenseManager.revision,
      now.year,
      now.month,
      Object.hashAll(_customCategories.map((c) => c.name)),
    );
    final cached = _monthByCategory;
    if (cached != null && _monthByCategoryKey == key) return cached;
    final bucket = _bucketer();
    final totals = <String, double>{};
    for (final e in _expenseManager.expenses) {
      if (e.date.year != now.year || e.date.month != now.month) continue;
      final k = bucket(e.category);
      totals[k] = (totals[k] ?? 0) + e.amount;
    }
    _monthByCategory = totals;
    _monthByCategoryKey = key;
    return totals;
  }

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

  Map<String, double> get currentMonthCategoryTotals =>
      Map.of(_currentMonthByCategory());

  List<Expense> getCurrentMonthExpensesByCategory(String category) {
    return currentMonthExpenses
        .where((expense) => categoryBucket(expense.category) == category)
        .toList();
  }

  double getCurrentMonthCategoryExpenses(String category) =>
      _currentMonthByCategory()[category] ?? 0.0;

  /// True if [d] falls in [period]. Calendar based with whole-day edges:
  /// the week follows the Sunday/Monday setting, and a custom range covers
  /// its start day through the end of its end day.
  static bool dateInPeriod(DateTime d, FilterPeriod period,
      {DateTime? customStart, DateTime? customEnd, DateTime? now}) {
    final n = now ?? DateTime.now();
    switch (period) {
      case FilterPeriod.weekly:
        final s = AppPrefs.instance.weekStartOf(n);
        final e = DateTime(s.year, s.month, s.day + 7);
        return !d.isBefore(s) && d.isBefore(e);
      case FilterPeriod.monthly:
        return d.year == n.year && d.month == n.month;
      case FilterPeriod.yearly:
        return d.year == n.year;
      case FilterPeriod.allTime:
        return true;
      case FilterPeriod.custom:
        if (customStart == null || customEnd == null) return true;
        final s = DateTime(customStart.year, customStart.month, customStart.day);
        final e = DateTime(customEnd.year, customEnd.month, customEnd.day + 1);
        return !d.isBefore(s) && d.isBefore(e);
    }
  }

  /// Spending in [period]. Leaves out the automatic "Saved" entries (they
  /// aren't spending; see [savingsHistory] and the Savings screen).
  List<Expense> getExpensesByPeriodType(FilterPeriod period,
      {DateTime? customStart, DateTime? customEnd, String? accountId}) {
    final now = DateTime.now();
    return _expenseManager.expenses
        .where((e) =>
            !_isAutoSaved(e) &&
            (accountId == null || e.accountId == accountId) &&
            dateInPeriod(e.date, period,
                customStart: customStart, customEnd: customEnd, now: now))
        .toList();
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
    return periodSummary(period,
            customStart: customStart,
            customEnd: customEnd,
            accountId: accountId)
        .totals;
  }

  /// Spending in [period] in one pass: per-category totals and counts, and
  /// the overall total and count (the Categories screen shows all four).
  ({
    Map<String, double> totals,
    Map<String, int> counts,
    double total,
    int count,
  }) periodSummary(FilterPeriod period,
      {DateTime? customStart, DateTime? customEnd, String? accountId}) {
    final bucket = _bucketer();
    final totals = <String, double>{};
    final counts = <String, int>{};
    var total = 0.0;
    final expenses = getExpensesByPeriodType(period,
        customStart: customStart, customEnd: customEnd, accountId: accountId);
    for (final e in expenses) {
      final key = bucket(e.category);
      totals[key] = (totals[key] ?? 0) + e.amount;
      counts[key] = (counts[key] ?? 0) + 1;
      total += e.amount;
    }
    return (
      totals: totals,
      counts: counts,
      total: total,
      count: expenses.length,
    );
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
      Expense? old;
      for (final e in _expenseManager.expenses) {
        if (e.id == expense.id) old = e;
      }
      await _expenseManager.updateExpense(expense, _userId);
      await _resyncSavings();
      _refreshCalculations();
      // Limit alerts for what the edit added: the difference if it stayed
      // in the same category and month, else the whole amount (it's new
      // to that category / month).
      final sameMonth = old != null &&
          old.date.year == expense.date.year &&
          old.date.month == expense.date.month;
      final sameBucket = sameMonth && old.category == expense.category;
      final change = old == null ? expense.amount : expense.amount - old.amount;
      await _limitAlerts(expense,
          increase: sameBucket ? change : expense.amount,
          // Only a real change in amount (or a move into this month) adds
          // to the month; a category change alone doesn't.
          monthIncrease: sameMonth ? change : expense.amount);
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

  /// Edits several entries at once (multi-select "Edit"): one savings
  /// re-check and one refresh. Also used to undo such an edit.
  Future<void> updateMany(
      {List<Expense> expenses = const [],
      List<Income> incomes = const []}) async {
    if (expenses.isEmpty && incomes.isEmpty) return;
    try {
      for (final e in expenses) {
        await _expenseManager.updateExpense(e, _userId);
      }
      for (final i in incomes) {
        await _incomeManager.updateIncome(i, _userId);
      }
      await _resyncSavings();
      _refreshCalculations();
    } finally {
      notifyListeners();
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

  /// Deletes several entries at once (multi-select): one savings re-check
  /// and one refresh at the end instead of one per entry.
  Future<void> deleteMany(
      {List<String> expenseIds = const [],
      List<String> incomeIds = const []}) async {
    if (expenseIds.isEmpty && incomeIds.isEmpty) return;
    try {
      _isLoading = true;
      notifyListeners();
      final skipped = _skippedSavingsMonths;
      final skippedBefore = skipped.length;
      // One pass over each list (thousands of entries can go at once, e.g.
      // Delete by date), not one search per entry.
      final expenseSet = expenseIds.toSet();
      final incomeSet = incomeIds.toSet();
      for (final e in _expenseManager.expenses) {
        if (!expenseSet.contains(e.id)) continue;
        final month = _savedMonthOf(e);
        if (month != null) skipped.add(month);
      }
      for (final i in _incomeManager.incomes) {
        if (!incomeSet.contains(i.id)) continue;
        final month = _carryMonthOf(i);
        if (month != null) skipped.add(month);
      }
      await _expenseManager.deleteMany(expenseSet, _userId);
      await _incomeManager.deleteMany(incomeSet, _userId);
      if (skipped.length != skippedBefore) {
        await _setSkippedSavingsMonths(skipped);
      }
      await _resyncSavings();
    } catch (e) {
      throw Exception('Failed to delete entries: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Expenses and income dated [from]..[to] (both days included), for
  /// Settings → Delete by date. Month-end "Saved" entries and carried-over
  /// leftovers are left out: they follow each month's totals and update by
  /// themselves (a Saved entry goes away when its month is emptied).
  ({List<Expense> expenses, List<Income> incomes}) entriesInRange(
      DateTime from, DateTime to) {
    final start = _dateOnly(from);
    final end = DateTime(to.year, to.month, to.day + 1); // day after [to]
    bool inside(DateTime d) => !d.isBefore(start) && d.isBefore(end);
    return (
      expenses: [
        for (final e in _expenseManager.expenses)
          if (e.id != null && !_isAutoSaved(e) && inside(e.date)) e
      ],
      incomes: [
        for (final i in _incomeManager.incomes)
          if (i.id != null && !isCarryForwardEntry(i) && inside(i.date)) i
      ],
    );
  }

  /// Permanently deletes what [entriesInRange] finds (only the kinds
  /// asked for). Returns how many entries went.
  Future<int> deleteRange(DateTime from, DateTime to,
      {bool expenses = true, bool incomes = true}) async {
    final found = entriesInRange(from, to);
    final expenseIds = expenses
        ? [for (final e in found.expenses) e.id!]
        : const <String>[];
    final incomeIds =
        incomes ? [for (final i in found.incomes) i.id!] : const <String>[];
    await deleteMany(expenseIds: expenseIds, incomeIds: incomeIds);
    return expenseIds.length + incomeIds.length;
  }

  Future<void> deleteIncome(String incomeId) async {
    try {
      _isLoading = true;
      notifyListeners();
      // Same as the Saved entry: deleting a carried-over leftover yourself
      // means "not for this month", so it isn't recreated.
      final target =
          _incomeManager.incomes.where((i) => i.id == incomeId).firstOrNull;
      final carryMonth = target == null ? null : _carryMonthOf(target);
      if (carryMonth != null) {
        await _setSkippedSavingsMonths(_skippedSavingsMonths..add(carryMonth));
      }
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
    return _incomeManager.incomes
        .where((i) =>
            (accountId == null || i.accountId == accountId) &&
            dateInPeriod(i.date, period,
                customStart: customStart, customEnd: customEnd, now: now))
        .toList();
  }

  Future<void> loadIncomes() async {
    await _incomeManager.loadIncomes(_userId);
    notifyListeners();
  }

  double getCategoryBudget(String categoryName) {
    return _budgetManager.getCategoryBudget(categoryName, _customCategories);
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
    var newName = name.trim();
    if (newName.isEmpty) throw ArgumentError('Name can\'t be empty');
    // "Saved" is found by its name when month-end savings run, so its name
    // stays fixed (icon and colour can still change), and no other
    // category can take that name.
    if (old.name == savedCategoryName) newName = savedCategoryName;
    if (old.name != savedCategoryName &&
        newName.toLowerCase() == savedCategoryName.toLowerCase()) {
      throw ArgumentError('"$savedCategoryName" is used for month-end savings');
    }
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
    if (_customCategories
        .any((c) => c.id == categoryId && c.name == savedCategoryName)) {
      return; // month-end savings would just recreate it
    }
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
    // Recurring entries count too, so deleting a category that only has a
    // recurring bill still asks where to move it.
    for (final r in _recurring) {
      all[r.category] = (all[r.category] ?? 0) + 1;
    }
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
    // "Saved" stays: month-end savings would just recreate it.
    categoryIds = categoryIds
        .where((id) => !_customCategories
            .any((c) => c.id == id && c.name == savedCategoryName))
        .toSet();
    if (categoryIds.isEmpty) return;
    final snapshot = List<ExpenseCategory>.from(_customCategories);
    try {
      if (reassign.isNotEmpty) {
        await LocalStore.reassignExpenseCategories(reassign,
            userId: _userId);
        // Recurring entries follow too, or future ones would be created
        // under the deleted category (and land in "Other").
        var recurringChanged = false;
        for (var i = 0; i < _recurring.length; i++) {
          final to = reassign[_recurring[i].category];
          if (to != null) {
            _recurring[i] = _recurring[i].copyWith(category: to);
            recurringChanged = true;
          }
        }
        if (recurringChanged) await _saveRecurring();
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

  /// Real spending in the viewed month. The automatic "Saved" entry isn't
  /// spending, so it's left out (see [viewMonthSaved]).
  double get viewMonthTotalExpense => viewMonthExpenses
      .where((e) => !_isAutoSaved(e))
      .fold(0.0, (sum, e) => sum + e.amount);

  /// The viewed month's leftover that went into "Saved".
  double get viewMonthSaved => viewMonthExpenses
      .where(_isAutoSaved)
      .fold(0.0, (sum, e) => sum + e.amount);

  /// The viewed month's leftover carried into the next month.
  double get viewMonthCarriedOut {
    final tag = '$_autoCarryPrefix${_monthKey(_viewMonth)}';
    return _incomeManager.incomes
        .where((i) => i.tag == tag)
        .fold(0.0, (sum, i) => sum + i.amount);
  }

  /// Part of the viewed month's income that was carried in from last month.
  double get viewMonthCarriedIn => viewMonthIncomes
      .where(isCarryForwardEntry)
      .fold(0.0, (sum, i) => sum + i.amount);

  double get viewMonthIncome =>
      viewMonthIncomes.fold(0.0, (sum, i) => sum + i.amount);

  double get viewMonthLeft => viewMonthIncome - viewMonthTotalExpense;
  bool get viewMonthOverspent => viewMonthLeft < 0;
  double get viewMonthOverspentBy => viewMonthLeft < 0 ? -viewMonthLeft : 0;

  Map<String, double> get viewMonthCategoryTotals {
    final totals = <String, double>{};
    for (final e in viewMonthExpenses.where((e) => !_isAutoSaved(e))) {
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
    }
    // All at once: one write and one sort, however many come back.
    await _expenseManager.addMany(expenses, _userId);
    if (skipChanged) await _setSkippedSavingsMonths(skipped);
    await _resyncSavings();
    notifyListeners();
  }

  Future<void> restoreIncomes(List<Income> incomes) async {
    final skipped = _skippedSavingsMonths;
    var skipChanged = false;
    for (final i in incomes) {
      final carryMonth = _carryMonthOf(i);
      if (carryMonth != null) skipChanged |= skipped.remove(carryMonth);
    }
    await _incomeManager.addMany(incomes, _userId);
    if (skipChanged) await _setSkippedSavingsMonths(skipped);
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
    await _resyncSavings(); // it may have landed in a closed month
    notifyListeners();
  }

  Future<void> updateRecurring(RecurringEntry entry) async {
    final i = _recurring.indexWhere((r) => r.id == entry.id);
    if (i == -1) return;
    _recurring[i] = entry;
    await _saveRecurring();
    await _processRecurring();
    await _resyncSavings();
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
    await _resyncSavings();
    notifyListeners();
  }

  Future<void> _processRecurring() async {
    final today = _dateOnly(DateTime.now());
    var changed = false;
    for (var i = 0; i < _recurring.length; i++) {
      var r = _recurring[i];
      if (!r.active) continue;
      // Catch-up cap (104 weeks / 24 months / 3 years): after a long gap
      // only the most recent missed ones are added, and the older ones are
      // skipped for good instead of arriving in batches on later opens.
      final missed = <DateTime>[];
      var due = r.nextDue;
      while (!due.isAfter(today) && missed.length < 5000) {
        missed.add(due);
        due = r.nextAfter(due);
      }
      if (missed.isEmpty) continue;
      final skip = missed.length > r.catchUpLimit
          ? missed.length - r.catchUpLimit
          : 0;
      for (final d in missed.skip(skip)) {
        await _createFromRecurring(r.copyWith(nextDue: d), d);
      }
      r = r.copyWith(nextDue: due);
      changed = true;
      _recurring[i] = r;
    }
    if (changed) await _saveRecurring();
  }

  /// Income / category-limit alerts (and 80% warnings) for an expense that
  /// was edited or added automatically.
  Future<void> _limitAlerts(Expense expense,
          {required double increase, double? monthIncrease}) =>
      _notificationManager.triggerExpenseNotifications(
        expense: expense,
        allExpenses: _expenseManager.expenses,
        monthlyIncome: totalIncomeThisMonth,
        categoryBudget: getCategoryBudget(expense.category),
        categorySpent: getCategoryExpenses(expense.category),
        isFirstExpense: false,
        increase: increase,
        monthIncrease: monthIncrease,
        checkLargePayment: false,
      );

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
          // Marks it as automatic (e.g. the daily reminder ignores it).
          tag: 'recurring-${r.id}',
          createdAt: now,
          updatedAt: now,
        ),
        _userId,
      );
    } else {
      final expense = Expense(
        amount: r.amount,
        description: r.title,
        category: r.category,
        date: due,
        paymentApp: 'Recurring',
        notes: r.notes,
        accountId: accountId,
        createdAt: now,
        updatedAt: now,
      );
      await _expenseManager.addExpense(expense, _userId);
      // A rent that pushes Bills over its limit warns like a manual one.
      await _limitAlerts(expense, increase: r.amount);
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

  /// Tag stored in Income.tag for a month's leftover carried into the next
  /// month, e.g. "auto-carry-2026-09" (dated 1 Oct 2026).
  static const String _autoCarryPrefix = 'auto-carry-';

  /// True for the automatic "carried over" income.
  static bool isCarryForwardEntry(Income i) =>
      i.tag?.startsWith(_autoCarryPrefix) ?? false;

  /// Month key ("2026-09") a carried-over income came from.
  static String? _carryMonthOf(Income i) => isCarryForwardEntry(i)
      ? i.tag!.substring(_autoCarryPrefix.length)
      : null;

  bool _savingsRunning = false;

  /// What happens to a month's leftover (Settings → Optional features):
  /// true  = it goes into a "Saved" entry on the month's last day (default);
  /// false = it's carried into next month as income on the 1st.
  bool get monthEndSavingsEnabled {
    final mode = LocalStore.getMeta('month_end_mode', userId: _userId);
    if (mode != null) return mode != 'carry';
    return LocalStore.getMeta('savings_enabled', userId: _userId) != '0';
  }

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

  /// Switches between saving the leftover and carrying it forward. The
  /// new choice applies from this month on (the first month it closes);
  /// earlier months keep the kind of entry they got, though its amount
  /// still follows late edits (see [_refreshMonthsBefore]).
  Future<void> setMonthEndSavings(bool on) async {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    // Record how every month closed so far was handled (old mode), so they
    // keep following late edits after the switch, including months that
    // ended with nothing left and so have no entry yet.
    final oldMode = monthEndSavingsEnabled ? 'save' : 'carry';
    final oldFrom = _parseMonthKey(
        LocalStore.getMeta('savings_from', userId: _userId) ?? '');
    if (oldFrom != null) {
      final modes = _closedMonthModes();
      for (var m = oldFrom;
          m.isBefore(thisMonth);
          m = DateTime(m.year, m.month + 1)) {
        modes.putIfAbsent(_monthKey(m), () => oldMode);
      }
      await _saveClosedMonthModes(modes);
    }
    // Order matters: a savings check running in between must never see the
    // new mode with the old start month.
    await LocalStore.setMeta('savings_from', _monthKey(thisMonth),
        userId: _userId);
    await LocalStore.setMeta('month_end_mode', on ? 'save' : 'carry',
        userId: _userId);
    notifyListeners();
  }

  /// Keeps every closed month's "Saved" entry equal to that month's
  /// leftover (income - spent, excluding the Saved entry itself). Creates,
  /// updates or removes it as needed, so late edits to a past month are
  /// reflected automatically. Months before this feature started are left
  /// alone (no back-filling).
  Future<void> _processMonthEndSavings() async {
    if (_userId == 0) return;
    if (_savingsRunning) {
      // A change arrived mid-run: run once more when this one ends, instead
      // of dropping it (Saved / carried-over would stay out of date).
      _savingsAgain = true;
      return;
    }
    _savingsRunning = true;
    try {
      do {
        _savingsAgain = false;
        await _savingsPass();
      } while (_savingsAgain);
    } finally {
      _savingsRunning = false;
    }
  }

  bool _savingsAgain = false;

  Future<void> _savingsPass() async {
    // Some stored entries couldn't be read: leftovers would come out wrong,
    // so Saved / carried-over entries are left exactly as they are.
    if (LocalStore.hasUnreadable) return;
    {
      final now = DateTime.now();
      final thisMonth = DateTime(now.year, now.month);

      // Before 3.1 the switch meant "Saved" or nothing. Someone who had it
      // off now gets carry-forward, starting with this month only, so
      // past months are never touched.
      if (LocalStore.getMeta('month_end_mode', userId: _userId) == null) {
        final wasOn =
            LocalStore.getMeta('savings_enabled', userId: _userId) != '0';
        await LocalStore.setMeta('month_end_mode', wasOn ? 'save' : 'carry',
            userId: _userId);
        if (!wasOn) {
          await LocalStore.setMeta('savings_from', _monthKey(thisMonth),
              userId: _userId);
        }
      }

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
      // Months closed before the last switch first (oldest first): a
      // carried-over amount feeds the next month's income, so the chain must
      // be updated in date order. Their entry keeps its kind, but its amount
      // still follows late edits (a back-dated expense).
      await _refreshMonthsBefore(from);
      final skipped = _skippedSavingsMonths;
      for (var m = from;
          m.isBefore(thisMonth);
          m = DateTime(m.year, m.month + 1)) {
        if (skipped.contains(_monthKey(m))) continue; // you deleted it
        await _reconcileSavingsFor(m);
      }
    }
  }

  /// For months before [from]: updates an existing Saved entry or
  /// carried-over income to the month's current leftover. Never creates
  /// one or switches its type, so the mode each month closed under stays.
  Future<void> _refreshMonthsBefore(DateTime from) async {
    final fromKey = _monthKey(from);
    // Remember how each earlier month closed ("save" / "carry"), so its
    // entry can come back if it was removed while the month had nothing
    // left (e.g. a mistaken back-dated expense that was then undone).
    final modes = _closedMonthModes();
    var changed = false;
    for (final e in _expenseManager.expenses) {
      final k = _savedMonthOf(e);
      if (k != null && !modes.containsKey(k)) {
        modes[k] = 'save';
        changed = true;
      }
    }
    for (final i in _incomeManager.incomes) {
      final tag = i.tag ?? '';
      if (!tag.startsWith(_autoCarryPrefix)) continue;
      final k = tag.substring(_autoCarryPrefix.length);
      if (!modes.containsKey(k)) {
        modes[k] = 'carry';
        changed = true;
      }
    }
    if (changed) await _saveClosedMonthModes(modes);
    final skipped = _skippedSavingsMonths;
    final ordered = modes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key)); // oldest first
    for (final e in ordered) {
      if (e.key.compareTo(fromKey) >= 0) continue;
      final m = _parseMonthKey(e.key);
      if (m == null) continue;
      // You deleted that month's Saved entry or carried-over income
      // yourself: it stays deleted (this used to bring a carried-over
      // income straight back).
      if (skipped.contains(e.key)) continue;
      await _reconcileSavingsFor(m, saveMode: e.value == 'save');
    }
  }

  Future<void> _saveClosedMonthModes(Map<String, String> modes) =>
      LocalStore.setMeta('closed_modes',
          modes.entries.map((e) => '${e.key}=${e.value}').join(','),
          userId: _userId);

  /// Month key -> "save" / "carry" for months closed before a mode switch.
  Map<String, String> _closedMonthModes() {
    final raw = LocalStore.getMeta('closed_modes', userId: _userId) ?? '';
    return {
      for (final part in raw.split(','))
        if (part.contains('=')) part.split('=')[0]: part.split('=')[1],
    };
  }

  /// [saveMode] defaults to the current setting; earlier months pass the
  /// mode they closed under.
  Future<void> _reconcileSavingsFor(DateTime m, {bool? saveMode}) async {
    final now = DateTime.now();
    final tag = '$_autoSavedPrefix${_monthKey(m)}';
    final carryTag = '$_autoCarryPrefix${_monthKey(m)}';
    saveMode ??= monthEndSavingsEnabled;
    bool inMonth(DateTime d) => d.year == m.year && d.month == m.month;

    // A month's own carried-over income never counts towards it (if its
    // date was moved back into the month, it would keep growing).
    final income = _incomeManager.incomes
        .where((i) => inMonth(i.date) && i.tag != carryTag)
        .fold(0.0, (sum, i) => sum + i.amount);
    final spent = _expenseManager.expenses
        .where((e) => inMonth(e.date) && !_isAutoSaved(e))
        .fold(0.0, (sum, e) => sum + e.amount);
    final left = double.parse((income - spent).toStringAsFixed(2));

    if (!saveMode) {
      // Carry-forward: no Saved entry for this month...
      for (final e in _expenseManager.expenses
          .where((e) => e.transactionId == tag)
          .toList()) {
        if (e.id != null) await _expenseManager.deleteExpense(e.id!, _userId);
      }
      await _reconcileCarryFor(m, carryTag, left);
      return;
    }
    // ...and in Saved mode, no carried-over income from it.
    for (final i
        in _incomeManager.incomes.where((i) => i.tag == carryTag).toList()) {
      if (i.id != null) await _incomeManager.deleteIncome(i.id!, _userId);
    }

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

  /// Keeps month [m]'s carried-over income (dated the 1st of the next
  /// month) equal to its leftover; removes it when nothing is left.
  Future<void> _reconcileCarryFor(DateTime m, String carryTag, double left) async {
    final now = DateTime.now();
    final entries =
        _incomeManager.incomes.where((i) => i.tag == carryTag).toList();
    for (final extra in entries.skip(1)) {
      if (extra.id != null) {
        await _incomeManager.deleteIncome(extra.id!, _userId);
      }
    }
    final existing = entries.isEmpty ? null : entries.first;

    if (left > 0) {
      if (existing == null) {
        await _incomeManager.addIncome(
          Income(
            amount: left,
            title: 'Carried over from ${DateFormat('MMMM yyyy').format(m)}',
            source: 'Leftover',
            date: DateTime(m.year, m.month + 1, 1),
            notes: 'Leftover (income − spent), kept up to date automatically',
            accountId: defaultAccount?.id,
            tag: carryTag,
            createdAt: now,
            updatedAt: now,
          ),
          _userId,
        );
      } else {
        // Its date is fixed: the 1st of the next month.
        final day = DateTime(m.year, m.month + 1, 1);
        final d = existing.date;
        final dateMoved =
            d.year != day.year || d.month != day.month || d.day != 1;
        if (dateMoved || (existing.amount - left).abs() >= 0.005) {
          await _incomeManager.updateIncome(
            existing.copyWith(
                amount: left, date: dateMoved ? day : d, updatedAt: now),
            _userId,
          );
        }
      }
    } else if (existing?.id != null) {
      await _incomeManager.deleteIncome(existing!.id!, _userId);
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

  // ==================== SAVINGS OVERVIEW ====================

  /// This month so far: income minus spending (what month-end will save or
  /// carry over, if nothing else changes).
  double get thisMonthLeft {
    final now = DateTime.now();
    bool inMonth(DateTime d) => d.year == now.year && d.month == now.month;
    final income = _incomeManager.incomes
        .where((i) => inMonth(i.date))
        .fold(0.0, (s, i) => s + i.amount);
    final spent = _expenseManager.expenses
        .where((e) => inMonth(e.date) && !_isAutoSaved(e))
        .fold(0.0, (s, e) => s + e.amount);
    return income - spent;
  }

  /// Carried in from last month, included in this month's income.
  double get thisMonthCarriedIn {
    final now = DateTime.now();
    return _incomeManager.incomes
        .where((i) =>
            isCarryForwardEntry(i) &&
            i.date.year == now.year &&
            i.date.month == now.month)
        .fold(0.0, (s, i) => s + i.amount);
  }

  /// Closed months that have a Saved entry or a carried-over leftover,
  /// newest first, with that month's income and real spending.
  List<MonthSavings> get savingsHistory {
    final byMonth = <String, MonthSavings>{};
    MonthSavings slot(String key) {
      final m = _parseMonthKey(key)!;
      return byMonth.putIfAbsent(key, () {
        bool inMonth(DateTime d) => d.year == m.year && d.month == m.month;
        return MonthSavings(
          month: m,
          income: _incomeManager.incomes
              .where((i) => inMonth(i.date))
              .fold(0.0, (s, i) => s + i.amount),
          spent: _expenseManager.expenses
              .where((e) => inMonth(e.date) && !_isAutoSaved(e))
              .fold(0.0, (s, e) => s + e.amount),
        );
      });
    }

    for (final e in _expenseManager.expenses.where(_isAutoSaved)) {
      final key = _savedMonthOf(e);
      if (key == null || _parseMonthKey(key) == null) continue;
      slot(key).savedEntry = e;
    }
    for (final i in _incomeManager.incomes.where(isCarryForwardEntry)) {
      final key = _carryMonthOf(i);
      if (key == null || _parseMonthKey(key) == null) continue;
      slot(key).carryEntry = i;
    }
    return byMonth.values.toList()
      ..sort((a, b) => b.month.compareTo(a.month));
  }

  /// Total put into "Saved" for months whose last day falls in [period].
  double savedInPeriod(FilterPeriod period,
          {DateTime? customStart, DateTime? customEnd}) =>
      _expenseManager.expenses
          .where((e) =>
              _isAutoSaved(e) &&
              dateInPeriod(e.date, period,
                  customStart: customStart, customEnd: customEnd))
          .fold(0.0, (s, e) => s + e.amount);

  int savedMonthsInPeriod(FilterPeriod period,
          {DateTime? customStart, DateTime? customEnd}) =>
      _expenseManager.expenses
          .where((e) =>
              _isAutoSaved(e) &&
              dateInPeriod(e.date, period,
                  customStart: customStart, customEnd: customEnd))
          .length;

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
    final old = _debts[i];
    // A settled entry's recorded income/expense follows amount / name edits.
    if (entry.settled &&
        (old.amount != entry.amount || old.person != entry.person)) {
      await _updateSettlement(entry);
    }
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
      final entry = _settlementId(d);
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

  /// Current id of a settled debt's recorded income/expense. It's linked by
  /// a tag that survives delete + undo (which gives the entry a new id);
  /// older entries saved the id itself, which is still checked.
  String? _settlementId(DebtEntry d) {
    final key = d.settlementEntryId;
    if (key == null) return null;
    if (d.isLent) {
      for (final inc in _incomeManager.incomes) {
        if (inc.tag == key || inc.id == key) return inc.id;
      }
    } else {
      for (final e in _expenseManager.expenses) {
        if (e.transactionId == key || e.id == key) return e.id;
      }
    }
    return null;
  }

  Future<void> _updateSettlement(DebtEntry d) async {
    final id = _settlementId(d);
    if (id == null) return;
    final now = DateTime.now();
    if (d.isLent) {
      for (final inc in _incomeManager.incomes.where((i) => i.id == id)) {
        await updateIncome(inc.copyWith(
            amount: d.amount,
            title: 'Repaid by ${d.person}',
            source: d.person,
            updatedAt: now));
        return;
      }
    } else {
      for (final e in _expenseManager.expenses.where((e) => e.id == id)) {
        await updateExpense(e.copyWith(
            amount: d.amount,
            description: 'Repaid ${d.person}',
            updatedAt: now));
        return;
      }
    }
  }

  /// Logs a settlement and returns the tag that links it to the debt.
  Future<String?> _recordSettlement(DebtEntry d) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final note = 'Settled from Lent & Borrowed'
        '${d.note == null || d.note!.isEmpty ? '' : ' · ${d.note}'}';
    final tag = 'debt-${d.id}-${now.millisecondsSinceEpoch}';
    if (d.isLent) {
      await addIncome(Income(
        amount: d.amount,
        title: 'Repaid by ${d.person}',
        source: d.person,
        date: today,
        notes: note,
        accountId: defaultAccount?.id,
        tag: tag,
        createdAt: now,
        updatedAt: now,
      ));
      return _incomeManager.incomes.any((i) => i.tag == tag) ? tag : null;
    }
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
    return _expenseManager.expenses.any((e) => e.transactionId == tag)
        ? tag
        : null;
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

  double getCategoryExpenses(String category) =>
      _currentMonthByCategory()[category] ?? 0.0;
}

/// One closed month in the Savings screen.
class MonthSavings {
  final DateTime month;
  final double income;
  final double spent;
  Expense? savedEntry;
  Income? carryEntry;

  MonthSavings({required this.month, required this.income, required this.spent});

  double get saved => savedEntry?.amount ?? 0;
  double get carried => carryEntry?.amount ?? 0;
  double get amount => saved + carried;
}
