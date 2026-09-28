import 'package:flutter/material.dart';
import '../../models/expense_models.dart';
import '../../services/local_store.dart';

class BudgetManager {
  final Map<String, double> _categoryBudgets = {};
  double _monthlyBudget = 25000.0;

  double get monthlyBudget => _monthlyBudget;
  Map<String, double> get categoryBudgets => _categoryBudgets;

  void initialize(double monthlyBudget, Map<String, double> categoryBudgets) {
    _monthlyBudget = monthlyBudget;
    _categoryBudgets.clear();
    _categoryBudgets.addAll(categoryBudgets);
  }

  Future<void> updateMonthlyBudget(double budget, int userId) async {
    await LocalStore.updateMonthlyBudget(budget, userId: userId);
    _monthlyBudget = budget;
  }

  double getCategoryBudget(
    String categoryName,
    List<ExpenseCategory> customCategories,
  ) {
    final customCategory = customCategories.firstWhere(
      (cat) => cat.name == categoryName,
      orElse: () => ExpenseCategory(
        id: '',
        name: '',
        icon: '',
        color: Colors.transparent,
      ),
    );

    if (customCategory.id.isNotEmpty) {
      return _categoryBudgets[customCategory.id] ?? 0.0;
    }
    return 0.0;
  }

  Future<void> setCategoryBudget(
    String categoryName,
    double budget,
    List<ExpenseCategory> customCategories,
    int userId,
  ) async {
    String categoryId = '';

    final customCategory = customCategories.firstWhere(
      (cat) => cat.name == categoryName,
      orElse: () => ExpenseCategory(
        id: '',
        name: '',
        icon: '',
        color: Colors.transparent,
      ),
    );

    if (customCategory.id.isNotEmpty) {
      categoryId = customCategory.id;
    }

    if (categoryId.isEmpty) {
      throw Exception('Category not found: $categoryName');
    }

    await LocalStore.updateCategoryBudget(
      categoryId,
      budget,
      userId: userId,
    );
    _categoryBudgets[categoryId] = budget;
  }

  double getCustomCategoryBudget(String categoryId) {
    return _categoryBudgets[categoryId] ?? 0.0;
  }

  Future<void> setCustomCategoryBudget(
    String categoryId,
    double budget,
    int userId,
  ) async {
    await LocalStore.updateCategoryBudget(
      categoryId,
      budget,
      userId: userId,
    );
    _categoryBudgets[categoryId] = budget;
  }

  bool isCategoryOverBudget(
    String category,
    double currentMonthCategoryExpenses,
    List<ExpenseCategory> customCategories,
  ) {
    final budget = getCategoryBudget(category, customCategories);
    return currentMonthCategoryExpenses > budget && budget > 0;
  }

  double getCategoryBudgetExcess(
    String category,
    double currentMonthCategoryExpenses,
    List<ExpenseCategory> customCategories,
  ) {
    final budget = getCategoryBudget(category, customCategories);
    return currentMonthCategoryExpenses - budget;
  }

  // Budget-related computed values
  bool isOverBudget(double currentMonthTotal) =>
      currentMonthTotal > _monthlyBudget;
  double budgetExcess(double currentMonthTotal) =>
      currentMonthTotal - _monthlyBudget;
  double budgetRemaining(double currentMonthTotal) =>
      _monthlyBudget - currentMonthTotal;
  double budgetUsagePercentage(double currentMonthTotal) =>
      _monthlyBudget > 0 ? (currentMonthTotal / _monthlyBudget) * 100 : 0;

  /// Clear all data
  void clear() {
    _categoryBudgets.clear();
    _monthlyBudget = 25000.0;
  }
}
