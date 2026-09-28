import 'package:flutter/material.dart';
import '../../models/expense_models.dart';
import '../../services/local_store.dart';

/// Per-category monthly limits (the overall monthly budget was replaced by
/// income tracking).
class BudgetManager {
  final Map<String, double> _categoryBudgets = {};

  Map<String, double> get categoryBudgets => _categoryBudgets;

  void initialize(Map<String, double> categoryBudgets) {
    _categoryBudgets.clear();
    _categoryBudgets.addAll(categoryBudgets);
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

  void clear() => _categoryBudgets.clear();
}
