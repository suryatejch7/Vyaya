import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/expense_models.dart';
import '../models/user_settings.dart' as models;
import 'backup_service.dart';

/// All app data, stored on the device in SharedPreferences (`ls_*` keys,
/// which is also what Backup / Restore copies). Nothing here touches the
/// network.
class LocalStore {
  static SharedPreferences? _prefs;

  // Storage keys
  static const String _usersKey = 'ls_users';
  static const String _settingsPrefix = 'ls_settings_';
  static const String _expensesPrefix = 'ls_expenses_';
  static const String _incomesPrefix = 'ls_incomes_';
  static const String _nextUserIdKey = 'ls_next_user_id';
  static const String _nextExpenseIdKey = 'ls_next_expense_id';
  static const String _nextIncomeIdKey = 'ls_next_income_id';

  /// Must be called before any other method.
  static Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _removeLegacyCacheKeys();
  }

  /// The old online version kept an offline copy of the server's expenses
  /// and settings plus a "last sync" time. The ls_* keys already hold all of
  /// it, so these are just duplicates taking space (and riding along in
  /// Android's backup).
  static Future<void> _removeLegacyCacheKeys() async {
    for (final key in _p.getKeys().toList()) {
      if (key.startsWith('cached_expenses') ||
          key.startsWith('cached_settings') ||
          key == 'last_sync_timestamp' ||
          key == 'cached_user_id') {
        await _p.remove(key);
      }
    }
  }

  static SharedPreferences get _p {
    if (_prefs == null) {
      throw Exception(
        'Local storage not initialized. Call LocalStore.initialize() first.',
      );
    }
    return _prefs!;
  }

  static int _nextId(String key) {
    final current = _p.getInt(key) ?? 0;
    final next = current + 1;
    _p.setInt(key, next);
    return next;
  }

  // ==================== USER OPERATIONS ====================

  static Future<models.User> createUser(String userName) async {
    final id = _nextId(_nextUserIdKey);
    final now = DateTime.now();
    final user = models.User(
      id: id,
      userName: userName,
      createdAt: now,
      updatedAt: now,
    );

    final users = _loadUsersRaw();
    users.add(user.toJson());
    await _p.setString(_usersKey, jsonEncode(users));
    BackupService.autoSave();
    return user;
  }

  static Future<models.User?> getUserById(int userId) async {
    final users = _loadUsersRaw();
    for (final u in users) {
      if (u['id'] == userId) {
        return models.User.fromJson(u);
      }
    }
    return null;
  }

  static Future<models.User?> getUserByUsername(String userName) async {
    final users = _loadUsersRaw();
    for (final u in users) {
      if (u['user_name'] == userName) {
        return models.User.fromJson(u);
      }
    }
    return null;
  }

  static Future<bool> isUsernameTaken(String userName) async {
    final user = await getUserByUsername(userName);
    return user != null;
  }

  static Future<List<models.User>> getAllUsers() async {
    final users = _loadUsersRaw();
    return users.map((u) => models.User.fromJson(u)).toList();
  }

  static Future<void> updateUserName(String userName,
      {required int userId}) async {
    final users = _loadUsersRaw();
    for (int i = 0; i < users.length; i++) {
      if (users[i]['id'] == userId) {
        users[i]['user_name'] = userName;
        users[i]['updated_at'] = DateTime.now().toIso8601String();
        break;
      }
    }
    await _p.setString(_usersKey, jsonEncode(users));
    BackupService.autoSave();
  }

  // ==================== SETTINGS OPERATIONS ====================

  static Future<models.UserSettings> createDefaultUserSettings(
      int userId) async {
    final now = DateTime.now();
    final settings = models.UserSettings(
      userId: userId,
      monthlyBudget: 25000.0,
      currency: '₹',
      categoryBudgets: {},
      customCategories: ExpenseCategory.getDefaultCategories(),
      createdAt: now,
      updatedAt: now,
    );
    await _saveSettings(userId, settings);
    return settings;
  }

  static Future<models.UserSettings> getUserSettings(
      {required int userId}) async {
    final json = _p.getString('$_settingsPrefix$userId');
    if (json == null) {
      return await createDefaultUserSettings(userId);
    }
    return models.UserSettings.fromJson(jsonDecode(json));
  }

  static Future<void> saveUserSettings(models.UserSettings settings) async {
    await _saveSettings(settings.userId, settings);
  }

  static Future<void> updateMonthlyBudget(double budget,
      {required int userId}) async {
    final settings = await getUserSettings(userId: userId);
    final updated = settings.copyWith(
      monthlyBudget: budget,
      updatedAt: DateTime.now(),
    );
    await _saveSettings(userId, updated);
  }

  static Future<void> updateCategoryBudget(String categoryId, double budget,
      {required int userId}) async {
    final settings = await getUserSettings(userId: userId);
    settings.categoryBudgets[categoryId] = budget;
    await _saveSettings(
      userId,
      settings.copyWith(updatedAt: DateTime.now()),
    );
  }

  static Future<void> saveCustomCategories(List<ExpenseCategory> categories,
      {required int userId}) async {
    final settings = await getUserSettings(userId: userId);
    final updated = settings.copyWith(
      customCategories: categories,
      updatedAt: DateTime.now(),
    );
    await _saveSettings(userId, updated);
  }

  static Future<void> saveAccounts(List<BankAccount> accounts,
      {required int userId}) async {
    final settings = await getUserSettings(userId: userId);
    final updated = settings.copyWith(
      accounts: accounts,
      updatedAt: DateTime.now(),
    );
    await _saveSettings(userId, updated);
  }

  // ==================== EXPENSE OPERATIONS ====================

  static Future<String> addExpense(Expense expense, int userId) async {
    final id = _nextId(_nextExpenseIdKey).toString();
    final expenses = _loadExpensesRaw(userId);
    final data = expense.toJson();
    data['id'] = id;
    data['user_id'] = userId;
    expenses.add(data);
    await _p.setString('$_expensesPrefix$userId', jsonEncode(expenses));
    BackupService.autoSave();
    return id;
  }

  static Future<void> updateExpense(Expense expense, int userId) async {
    if (expense.id == null) {
      throw Exception('Expense ID is required for update');
    }
    final expenses = _loadExpensesRaw(userId);
    for (int i = 0; i < expenses.length; i++) {
      if (expenses[i]['id'].toString() == expense.id) {
        final data = expense.toJson();
        data['user_id'] = userId;
        expenses[i] = data;
        break;
      }
    }
    await _p.setString('$_expensesPrefix$userId', jsonEncode(expenses));
    BackupService.autoSave();
  }

  /// Counts expenses per category name across ALL stored expenses.
  static Future<Map<String, int>> getExpenseCountsByCategory(
      {required int userId}) async {
    final counts = <String, int>{};
    for (final e in _loadExpensesRaw(userId)) {
      final cat = (e['category'] ?? 'Other').toString();
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    return counts;
  }

  /// Renames the category on every stored expense per [mapping] (old -> new).
  /// Single pass, single write. Returns how many expenses changed.
  static Future<int> reassignExpenseCategories(Map<String, String> mapping,
      {required int userId}) async {
    if (mapping.isEmpty) return 0;
    final expenses = _loadExpensesRaw(userId);
    final now = DateTime.now().toIso8601String();
    var changed = 0;
    for (final e in expenses) {
      final target = mapping[(e['category'] ?? 'Other').toString()];
      if (target != null) {
        e['category'] = target;
        e['updated_at'] = now;
        changed++;
      }
    }
    if (changed > 0) {
      await _p.setString('$_expensesPrefix$userId', jsonEncode(expenses));
      BackupService.autoSave();
    }
    return changed;
  }

  /// Moves every expense and income on account [from] to [to] (null = no
  /// account). Returns how many entries changed.
  static Future<int> reassignAccount(String from, String? to,
      {required int userId}) async {
    final now = DateTime.now().toIso8601String();
    var changed = 0;
    for (final prefix in [_expensesPrefix, _incomesPrefix]) {
      final rows = prefix == _expensesPrefix
          ? _loadExpensesRaw(userId)
          : _loadIncomesRaw(userId);
      var n = 0;
      for (final r in rows) {
        if (r['account_id']?.toString() == from) {
          r['account_id'] = to;
          r['updated_at'] = now;
          n++;
        }
      }
      if (n > 0) {
        await _p.setString('$prefix$userId', jsonEncode(rows));
        changed += n;
      }
    }
    if (changed > 0) BackupService.autoSave();
    return changed;
  }

  static Future<void> deleteExpense(String expenseId, int userId) async {
    final expenses = _loadExpensesRaw(userId);
    expenses.removeWhere((e) => e['id'].toString() == expenseId);
    await _p.setString('$_expensesPrefix$userId', jsonEncode(expenses));
    BackupService.autoSave();
  }

  static Future<List<Expense>> getExpenses({
    required int userId,
    String? category,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final expenses = _loadExpensesRaw(userId);
    var result = expenses.map((e) => Expense.fromJson(e)).toList();

    if (category != null) {
      result = result.where((e) => e.category == category).toList();
    }
    if (startDate != null) {
      result = result.where((e) => !e.date.isBefore(startDate)).toList();
    }
    if (endDate != null) {
      result = result.where((e) => !e.date.isAfter(endDate)).toList();
    }

    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  // ==================== INCOME OPERATIONS ====================

  static Future<String> addIncome(Income income, int userId) async {
    final id = _nextId(_nextIncomeIdKey).toString();
    final incomes = _loadIncomesRaw(userId);
    final data = income.toJson();
    data['id'] = id;
    data['user_id'] = userId;
    incomes.add(data);
    await _p.setString('$_incomesPrefix$userId', jsonEncode(incomes));
    BackupService.autoSave();
    return id;
  }

  static Future<void> updateIncome(Income income, int userId) async {
    final incomes = _loadIncomesRaw(userId);
    for (int i = 0; i < incomes.length; i++) {
      if (incomes[i]['id'].toString() == income.id) {
        final data = income.toJson();
        data['user_id'] = userId;
        incomes[i] = data;
        break;
      }
    }
    await _p.setString('$_incomesPrefix$userId', jsonEncode(incomes));
    BackupService.autoSave();
  }

  static Future<void> deleteIncome(String incomeId, int userId) async {
    final incomes = _loadIncomesRaw(userId);
    incomes.removeWhere((i) => i['id'].toString() == incomeId);
    await _p.setString('$_incomesPrefix$userId', jsonEncode(incomes));
    BackupService.autoSave();
  }

  static Future<List<Income>> getIncomes({required int userId}) async {
    final incomes = _loadIncomesRaw(userId);
    final result = incomes.map((i) => Income.fromJson(i)).toList();
    result.sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  // ==================== EXTRA LISTS & META ====================
  // Stored under ls_<name>_<userId> so backups/restores include them.
  // Used for: recurring entries, lent/borrowed, month-end savings marker.

  static Future<List<Map<String, dynamic>>> getJsonList(String name,
      {required int userId}) async {
    final json = _p.getString('ls_${name}_$userId');
    if (json == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(json) as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  static Future<void> saveJsonList(
      String name, List<Map<String, dynamic>> items,
      {required int userId}) async {
    await _p.setString('ls_${name}_$userId', jsonEncode(items));
    BackupService.autoSave();
  }

  static String? getMeta(String name, {required int userId}) =>
      _p.getString('ls_${name}_$userId');

  static Future<void> setMeta(String name, String value,
      {required int userId}) async {
    await _p.setString('ls_${name}_$userId', value);
    BackupService.autoSave();
  }

  // ==================== DATA MANAGEMENT ====================

  /// Clears ALL app data from local storage.
  static Future<void> resetAllData() async {
    await _p.clear();
    // Re-initialize prefs reference after clear
    _prefs = await SharedPreferences.getInstance();
  }

  /// Clears data for a specific user only.
  static Future<void> resetUserData(int userId) async {
    await _p.remove('$_expensesPrefix$userId');
    await _p.remove('$_incomesPrefix$userId');
    await _p.remove('$_settingsPrefix$userId');
    await _p.remove('ls_recurring_$userId');
    await _p.remove('ls_debts_$userId');
    await _p.remove('ls_savings_through_$userId');
    await _p.remove('ls_savings_from_$userId');
    await _p.remove('ls_savings_enabled_$userId');
    await _p.remove('ls_savings_skip_$userId');
  }

  // ==================== PRIVATE HELPERS ====================

  static List<Map<String, dynamic>> _loadUsersRaw() {
    final json = _p.getString(_usersKey);
    if (json == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(json) as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  static Future<void> _saveSettings(
      int userId, models.UserSettings settings) async {
    await _p.setString(
      '$_settingsPrefix$userId',
      jsonEncode(settings.toJson()),
    );
    BackupService.autoSave();
  }

  static List<Map<String, dynamic>> _loadExpensesRaw(int userId) {
    final json = _p.getString('$_expensesPrefix$userId');
    if (json == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(json) as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  static List<Map<String, dynamic>> _loadIncomesRaw(int userId) {
    final json = _p.getString('$_incomesPrefix$userId');
    if (json == null) return [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(json) as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }
}
