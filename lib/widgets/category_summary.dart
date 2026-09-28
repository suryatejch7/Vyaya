import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../models/expense_models.dart';
import '../screens/categories_screen.dart';
import '../services/app_prefs.dart';

class CategorySummary extends StatefulWidget {
  const CategorySummary({super.key});

  @override
  State<CategorySummary> createState() => _CategorySummaryState();
}

class _CategorySummaryState extends State<CategorySummary> {

  @override
  Widget build(BuildContext context) {
    // Rebuilds when "Hide totals on Home" is toggled.
    return ListenableBuilder(
      listenable: AppPrefs.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return Consumer<ExpenseProvider>(
      builder: (context, expenseProvider, child) {
        // Use current month data instead of all-time
        final categoryTotals = expenseProvider.viewMonthCategoryTotals;
        final categories = expenseProvider.categories;
        final currentMonthTotal = expenseProvider.viewMonthTotalExpense;
        final currency = expenseProvider.currency;

        if (categoryTotals.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              expenseProvider.isViewingCurrentMonth
                  ? 'This Month by Category'
                  : 'By Category',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: categoryTotals.length,
                itemBuilder: (context, index) {
                  final categoryName = categoryTotals.keys.elementAt(index);
                  final amount = categoryTotals[categoryName]!;
                  final percentage = currentMonthTotal > 0 ? (amount / currentMonthTotal * 100) : 0.0;
                  // Category limits apply to the current month only.
                  final isOverBudget = expenseProvider.isViewingCurrentMonth &&
                      expenseProvider.isCategoryOverBudget(categoryName);
                  final budget = expenseProvider.getCategoryBudget(categoryName);

                  // Find the category object
                  final category = categories.firstWhere(
                    (cat) => cat.name == categoryName,
                    orElse: () => ExpenseCategory(
                      id: categoryName,
                      name: categoryName,
                      icon: '📦',
                      colorHex: '#747D8C',
                    ),
                  );

                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: GestureDetector(
                      onTap: () {
                        // Open the month being viewed on Home, not always
                        // the current one.
                        final m = expenseProvider.viewMonth;
                        final isCurrent = expenseProvider.isViewingCurrentMonth;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CategoryDetailScreen(
                              categoryName: categoryName,
                              filterPeriod: isCurrent
                                  ? FilterPeriod.monthly
                                  : FilterPeriod.custom,
                              customStartDate: isCurrent
                                  ? null
                                  : DateTime(m.year, m.month, 1),
                              customEndDate: isCurrent
                                  ? null
                                  : DateTime(m.year, m.month + 1, 0),
                            ),
                          ),
                        );
                      },
                      child: Container(
                      width: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isOverBudget
                              ? Colors.red.withValues(alpha: 0.5)
                              : category.color.withValues(alpha: 0.3),
                          width: 2,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF2A2A2A),
                            isOverBudget
                                ? Colors.red.withValues(alpha: 0.2)
                                : category.color.withValues(alpha: 0.2),
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            category.icon,
                            style: TextStyle(
                              fontSize: 22,
                              color: isOverBudget ? Colors.red : category.color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            category.displayName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppPrefs.instance.hideHomeTotals
                                ? '$currency••••'
                                : '$currency${amount.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isOverBudget ? Colors.red : Colors.white,
                            ),
                          ),
                          if (budget > 0)
                            Text(
                              '${percentage.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 9,
                                color: isOverBudget ? Colors.red : Colors.white60,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
