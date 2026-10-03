import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense_models.dart';
import '../providers/expense_provider.dart';
import '../services/app_prefs.dart';
import 'dart:math' as math;
import '../services/money_format.dart';


/// 00:00 on the first day of the week containing [d]: Sunday by default,
/// Monday if chosen in Settings → Optional features.
DateTime _weekStartOf(DateTime d) => AppPrefs.instance.weekStartOf(d);

/// True if [date] falls in the 7-day week beginning at [start].
bool _inWeek(DateTime date, DateTime start) {
  final next = DateTime(start.year, start.month, start.day + 7);
  return !date.isBefore(start) && date.isBefore(next);
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _selectedPeriod = 'Month';
  final List<String> _periods = ['Day', 'Week', 'Month', 'Year'];
  String? _selectedAccountId; // null means all accounts

  /// Spending only: the automatic month-end "Saved" entries are money kept,
  /// not spent, so they'd otherwise make every past month's spending equal
  /// its income.
  List<Expense> _getFilteredExpenses(ExpenseProvider provider) {
    return _base ??= provider.expenses
        .where((e) => !ExpenseProvider.isAutoSavedEntry(e))
        .where((e) =>
            _selectedAccountId == null || e.accountId == _selectedAccountId)
        .toList();
  }

  // Worked out once per rebuild and shared by the cards (each used to go
  // through every expense again). Cleared at the start of every build.
  List<Expense>? _base;
  double? _periodTotal;
  Map<String, double>? _categoryTotals;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Analytics',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              context.read<ExpenseProvider>().forceRefresh();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Analytics refreshed'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, child) {
          _base = null;
          _periodTotal = null;
          _categoryTotals = null;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPeriodSelector(),
                const SizedBox(height: 12),

                _buildAccountSelector(provider),
                const SizedBox(height: 20),

                _buildTotalSpendingCard(provider),
                const SizedBox(height: 20),

                _buildSpendingTrendCard(provider),
                const SizedBox(height: 20),

                _buildCategoryPieChart(provider),
                const SizedBox(height: 20),

                _buildTopCategoriesCard(provider),
                const SizedBox(height: 20),

                _buildBudgetTrackingCard(provider),
                const SizedBox(height: 20),

                _buildSpendingInsights(provider),
                const SizedBox(height: 20),

                _buildMonthlyComparison(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: _periods.map((period) {
          final isSelected = _selectedPeriod == period;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPeriod = period;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  period,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAccountSelector(ExpenseProvider provider) {
    final accounts = provider.accounts;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedAccountId,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A1A),
          icon: Icon(
            Icons.keyboard_arrow_down,
            color: Theme.of(context).colorScheme.primary,
          ),
          hint: Row(
            children: [
              Icon(
                Icons.account_balance_wallet,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text('All Accounts', style: TextStyle(color: Colors.white)),
            ],
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'All Accounts',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            ...accounts.map(
              (account) => DropdownMenuItem<String?>(
                value: account.id,
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      account.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _selectedAccountId = value;
            });
          },
        ),
      ),
    );
  }

  Widget _buildTotalSpendingCard(ExpenseProvider provider) {
    final periodData = _getPeriodData(provider);
    final previousPeriodData = _getPreviousPeriodData(provider);
    final currency = provider.currency;
    final changePercent = previousPeriodData > 0
        ? ((periodData - previousPeriodData) / previousPeriodData * 100)
        : 0.0;

    return _buildAnalyticsCard(
      title: 'Total Spending - $_selectedPeriod',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Shrinks to fit next to the change badge (big totals, small
              // phones, large font).
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$currency${formatAmount(periodData, 0)}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (changePercent != 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: changePercent > 0 ? Colors.red : Colors.green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        changePercent > 0
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${changePercent.abs().toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'vs Previous $_selectedPeriod: $currency${formatAmount(previousPeriodData, 0)}',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSpendingTrendCard(ExpenseProvider provider) {
    final expenses = _getFilteredExpenses(provider);
    final labels = _getTrendLabels();

    return _buildAnalyticsCard(
      title: 'Spending Trend',
      child: SizedBox(
        height: 180,
        // Own layer: scrolling the page doesn't redraw the chart.
        child: RepaintBoundary(
          child: CustomPaint(
            painter: SpendingTrendPainter(
              expenses: expenses,
              period: _selectedPeriod,
              labels: labels,
            ),
            size: const Size.fromHeight(180),
          ),
        ),
      ),
    );
  }

  List<String> _getTrendLabels() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Day':
        // Today in 6 blocks of 4 hours: 00:00, 04:00 … 20:00.
        return List.generate(
            6, (i) => '${(i * 4).toString().padLeft(2, '0')}:00');
      case 'Week':
        // This calendar week, in week order (Sun–Sat or Mon–Sun).
        return AppPrefs.instance.weekdayLabels;
      case 'Month':
        return List.generate(4, (i) => 'W${4 - i}').reversed.toList();
      case 'Year':
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return List.generate(6, (i) {
          final m = DateTime(now.year, now.month - (5 - i));
          return months[m.month - 1];
        });
      default:
        return [];
    }
  }

  Widget _buildCategoryPieChart(ExpenseProvider provider) {
    final categoryTotals = _getCategoryTotalsForPeriod(provider);
    final periodTotal = _getPeriodData(provider);
    final categories = provider.categories;

    if (categoryTotals.isEmpty) {
      return _buildAnalyticsCard(
        title: 'Category Breakdown',
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'No expenses in this period',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    // Build sorted entries with their category objects
    final sortedEntries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Get category colors in the same order
    final categoryColors = sortedEntries.map((entry) {
      final cat = categories.firstWhere(
        (c) => c.name == entry.key,
        orElse: () => ExpenseCategory(
          id: entry.key, name: entry.key, icon: '📦', colorHex: '#747D8C',
        ),
      );
      return cat.color;
    }).toList();

    return _buildAnalyticsCard(
      title: 'Category Breakdown',
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CategoryPieChartPainter(
                  categoryTotals: Map.fromEntries(sortedEntries),
                  colors: categoryColors,
                ),
                size: const Size.fromHeight(200),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: sortedEntries.asMap().entries.map((mapEntry) {
              final index = mapEntry.key;
              final entry = mapEntry.value;
              final percentage = periodTotal > 0
                  ? (entry.value / periodTotal * 100)
                  : 0.0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: categoryColors[index],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${entry.key} (${percentage.toStringAsFixed(0)}%)',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCategoriesCard(ExpenseProvider provider) {
    final categoryTotals = _getCategoryTotalsForPeriod(provider);
    final periodTotal = _getPeriodData(provider);
    final categories = provider.categories;
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedCategories.isEmpty) {
      return _buildAnalyticsCard(
        title: 'Top Categories',
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'No expenses in this period',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    final currency = provider.currency;

    return _buildAnalyticsCard(
      title: 'Top Categories',
      child: Column(
        children: sortedCategories.take(5).map((entry) {
          final categoryName = entry.key;
          final amount = entry.value;
          final percentage = periodTotal > 0
              ? (amount / periodTotal * 100)
              : 0.0;
          // Only show over budget for monthly view
          final isOverBudget =
              _selectedPeriod == 'Month' &&
              provider.isCategoryOverBudget(categoryName);

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

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isOverBudget
                    ? Colors.red.withValues(alpha: 0.5)
                    : Colors.grey.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isOverBudget
                        ? Colors.red.withValues(alpha: 0.2)
                        : category.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      category.icon,
                      style: TextStyle(
                        fontSize: 20,
                        color: isOverBudget ? Colors.red : category.color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(1)}% of total',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Shrinks a very large amount instead of overflowing.
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$currency${formatAmount(amount, 0)}',
                      style: TextStyle(
                        color: isOverBudget ? Colors.red : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBudgetTrackingCard(ExpenseProvider provider) {
    // Only show budget tracking for Month view since budgets are monthly
    if (_selectedPeriod != 'Month') {
      return _buildAnalyticsCard(
        title: 'Budget Tracking',
        child: const Center(
          child: Text(
            'Budget tracking is available in Month view',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final currency = provider.currency;

    return _buildAnalyticsCard(
      title: 'Budget Tracking',
      child: Column(
        children: [
          // Overall: this month's spending vs this month's income
          ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: provider.isOverspent
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: provider.isOverspent ? Colors.red : Colors.green,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Income vs Spent',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        provider.isOverspent ? 'Overspent' : 'On Track',
                        style: TextStyle(
                          color: provider.isOverspent
                              ? Colors.red
                              : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: provider.totalIncomeThisMonth > 0
                        ? (provider.currentMonthTotalExpense /
                                provider.totalIncomeThisMonth)
                            .clamp(0.0, 1.0)
                        : (provider.currentMonthTotalExpense > 0 ? 1.0 : 0.0),
                    backgroundColor: Colors.grey.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      provider.isOverspent ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Spent: $currency${formatAmount(provider.currentMonthTotalExpense, 0)}',
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Income: $currency${formatAmount(provider.totalIncomeThisMonth, 0)}',
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  if (provider.isOverspent) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Over by: $currency${formatAmount(provider.overspentBy, 0)}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Category Budgets
          ...provider.categories
              .where((category) {
                return provider.getCategoryBudget(category.name) > 0;
              })
              .map((category) {
                final budget = provider.getCategoryBudget(category.name);
                final spent = provider.getCategoryExpenses(category.name);
                final isOverBudget = spent > budget;
                final percentage = (spent / budget).clamp(0.0, 1.0);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOverBudget
                          ? Colors.red.withValues(alpha: 0.5)
                          : Colors.grey.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            category.icon,
                            style: TextStyle(
                              fontSize: 20,
                              color: isOverBudget ? Colors.red : category.color,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              category.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Shrinks large amounts instead of overflowing.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * 0.5),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                '$currency${formatAmount(spent, 0)} / $currency${formatAmount(budget, 0)}',
                                style: TextStyle(
                                  color:
                                      isOverBudget ? Colors.red : Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: percentage,
                        backgroundColor: Colors.grey.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isOverBudget ? Colors.red : category.color,
                        ),
                      ),
                      if (isOverBudget) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Over by: $currency${formatAmount((spent - budget), 0)}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
        ],
      ),
    );
  }

  Widget _buildSpendingInsights(ExpenseProvider provider) {
    final insights = _generateInsights(provider);

    return _buildAnalyticsCard(
      title: 'Spending Insights',
      child: Column(
        children: insights.map((insight) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Icon(insight['icon'], color: insight['color'], size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    insight['text'],
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMonthlyComparison(ExpenseProvider provider) {
    String title;
    List<String> labels;
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    switch (_selectedPeriod) {
      case 'Day':
        title = 'Last 7 Days';
        labels = List.generate(7, (i) {
          final date = now.subtract(Duration(days: 6 - i));
          return days[date.weekday - 1];
        });
        break;
      case 'Week':
        title = 'Last 4 Weeks';
        labels = List.generate(4, (i) => 'W${i + 1}');
        break;
      case 'Month':
        title = 'Last 6 Months';
        labels = List.generate(6, (i) {
          final m = DateTime(now.year, now.month - (5 - i));
          return months[m.month - 1];
        });
        break;
      case 'Year':
        title = 'Last 3 Years';
        labels = List.generate(3, (i) => '${now.year - 2 + i}');
        break;
      default:
        title = 'Comparison';
        labels = [];
    }

    return _buildAnalyticsCard(
      title: title,
      child: SizedBox(
        height: 160,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: ComparisonBarPainter(
              expenses: _getFilteredExpenses(provider),
              period: _selectedPeriod,
              labels: labels,
              currency: provider.currency,
            ),
            size: const Size.fromHeight(160),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  double _getPeriodData(ExpenseProvider provider) =>
      _periodTotal ??= _computePeriodData(provider);

  double _computePeriodData(ExpenseProvider provider) {
    final now = DateTime.now();
    final weekStart = _weekStartOf(now);
    // Ensure we're using the most up-to-date expenses, filtered by account
    final baseExpenses = _getFilteredExpenses(provider);
    final expenses = baseExpenses.where((expense) {
      switch (_selectedPeriod) {
        case 'Day':
          return expense.date.year == now.year &&
              expense.date.month == now.month &&
              expense.date.day == now.day;
        case 'Week':
          // Calendar week (Sun–Sat, or Mon–Sun if chosen).
          return _inWeek(expense.date, weekStart);
        case 'Month':
          return expense.date.year == now.year &&
              expense.date.month == now.month;
        case 'Year':
          return expense.date.year == now.year;
        default:
          return false;
      }
    }).toList(); // Convert to list to ensure we have fresh data

    final total = expenses.fold(0.0, (sum, expense) => sum + expense.amount);
    return total;
  }

  double _getPreviousPeriodData(ExpenseProvider provider) {
    final now = DateTime.now();
    // Ensure we're using the most up-to-date expenses, filtered by account
    final baseExpenses = _getFilteredExpenses(provider);
    final expenses = baseExpenses.where((expense) {
      switch (_selectedPeriod) {
        case 'Day':
          final yesterday = now.subtract(const Duration(days: 1));
          return expense.date.year == yesterday.year &&
              expense.date.month == yesterday.month &&
              expense.date.day == yesterday.day;
        case 'Week':
          final thisWeek = _weekStartOf(now);
          final lastWeek =
              DateTime(thisWeek.year, thisWeek.month, thisWeek.day - 7);
          return _inWeek(expense.date, lastWeek);
        case 'Month':
          final lastMonth = DateTime(now.year, now.month - 1);
          return expense.date.year == lastMonth.year &&
              expense.date.month == lastMonth.month;
        case 'Year':
          return expense.date.year == now.year - 1;
        default:
          return false;
      }
    }).toList(); // Convert to list to ensure we have fresh data

    final total = expenses.fold(0.0, (sum, expense) => sum + expense.amount);
    return total;
  }

  List<Map<String, dynamic>> _generateInsights(ExpenseProvider provider) {
    final insights = <Map<String, dynamic>>[];
    final categoryTotals = _getCategoryTotalsForPeriod(provider);
    final periodTotal = _getPeriodData(provider);
    final categories = provider.categories;
    final currency = provider.currency;

    if (categoryTotals.isNotEmpty) {
      final topCategory = categoryTotals.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      // Find the category object for display name
      final topCategoryObj = categories.firstWhere(
        (cat) => cat.name == topCategory.key,
        orElse: () => ExpenseCategory(
          id: topCategory.key,
          name: topCategory.key,
          icon: '📦',
          colorHex: '#747D8C',
        ),
      );

      insights.add({
        'icon': Icons.trending_up,
        'color': Colors.blue,
        'text':
            '${topCategoryObj.displayName} is your highest spending category this $_selectedPeriod ($currency${formatAmount(topCategory.value, 0)})',
      });
    }

    // Only show budget warnings for Month view
    if (_selectedPeriod == 'Month') {
      if (provider.isOverspent) {
        insights.add({
          'icon': Icons.warning,
          'color': Colors.red,
          'text':
              'You\'ve spent $currency${formatAmount(provider.overspentBy, 0)} more than your income this month',
        });
      }

      final overBudgetCategories = categories
          .where((category) => provider.isCategoryOverBudget(category.name))
          .length;
      if (overBudgetCategories > 0) {
        insights.add({
          'icon': Icons.category,
          'color': Colors.orange,
          'text':
              '$overBudgetCategories ${overBudgetCategories == 1 ? 'category is' : 'categories are'} over budget',
        });
      }
    }

    // Calculate average based on period
    final averageSpending = _calculateAverageSpending(provider, periodTotal);
    insights.add({
      'icon': Icons.calendar_today,
      'color': Colors.green,
      'text': averageSpending,
    });

    return insights;
  }

  /// Calculate average spending based on selected period
  String _calculateAverageSpending(
    ExpenseProvider provider,
    double periodTotal,
  ) {
    final now = DateTime.now();
    final currency = provider.currency;
    switch (_selectedPeriod) {
      case 'Day':
        return 'Total today: $currency${formatAmount(periodTotal, 0)}';
      case 'Week':
        final daysInWeek =
            DateTime(now.year, now.month, now.day)
                    .difference(_weekStartOf(now))
                    .inDays +
                1;
        final avg = daysInWeek > 0 ? periodTotal / daysInWeek : 0.0;
        return 'Average daily spending this week: $currency${formatAmount(avg, 0)}';
      case 'Month':
        final avg = now.day > 0 ? periodTotal / now.day : 0.0;
        return 'Average daily spending this month: $currency${formatAmount(avg, 0)}';
      case 'Year':
        final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays + 1;
        final avg = dayOfYear > 0 ? periodTotal / dayOfYear : 0.0;
        return 'Average daily spending this year: $currency${formatAmount(avg, 0)}';
      default:
        return 'Average daily spending: $currency${formatAmount((periodTotal / now.day), 0)}';
    }
  }

  /// Get category totals filtered by selected period and account
  Map<String, double> _getCategoryTotalsForPeriod(ExpenseProvider provider) =>
      _categoryTotals ??= _computeCategoryTotals(provider);

  Map<String, double> _computeCategoryTotals(ExpenseProvider provider) {
    final now = DateTime.now();
    final weekStart = _weekStartOf(now);
    final baseExpenses = _getFilteredExpenses(provider);
    final filteredExpenses = baseExpenses.where((expense) {
      switch (_selectedPeriod) {
        case 'Day':
          return expense.date.year == now.year &&
              expense.date.month == now.month &&
              expense.date.day == now.day;
        case 'Week':
          // Calendar week (Sun–Sat, or Mon–Sun if chosen).
          return _inWeek(expense.date, weekStart);
        case 'Month':
          return expense.date.year == now.year &&
              expense.date.month == now.month;
        case 'Year':
          return expense.date.year == now.year;
        default:
          return false;
      }
    }).toList();

    Map<String, double> totals = {};
    for (var expense in filteredExpenses) {
      final key = provider.categoryBucket(expense.category);
      totals[key] = (totals[key] ?? 0) + expense.amount;
    }
    return totals;
  }
}

// Custom Painters for Charts
class SpendingTrendPainter extends CustomPainter {
  final List<Expense> expenses;
  final String period;
  final List<String> labels;

  SpendingTrendPainter({
    required this.expenses,
    required this.period,
    required this.labels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelHeight = 20.0;
    const leftPadding = 40.0;
    const rightPadding = 10.0;
    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - labelHeight - 10;

    final dataPoints = _values;
    if (dataPoints.isEmpty) return;

    final maxValue = dataPoints.reduce(math.max);
    if (maxValue == 0) {
      // Draw "No data" text
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'No spending data',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(size.width / 2 - textPainter.width / 2, size.height / 2 - textPainter.height / 2),
      );
      return;
    }

    // Draw Y-axis labels (amounts)
    for (int i = 0; i <= 3; i++) {
      final value = maxValue * i / 3;
      final y = chartHeight - (chartHeight * i / 3) + 5;
      // Indian units: 950, 12K, 2.5L, 1.2Cr.
      final label = compactAmount(value);
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(color: Colors.grey, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(0, y - textPainter.height / 2));

      // Draw horizontal grid line
      final gridPaint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.1)
        ..strokeWidth = 0.5;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
    }

    // Calculate points
    final points = <Offset>[];
    for (int i = 0; i < dataPoints.length; i++) {
      final x = leftPadding + (i / (dataPoints.length - 1).clamp(1, double.infinity)) * chartWidth;
      final y = chartHeight - (dataPoints[i] / maxValue) * chartHeight + 5;
      points.add(Offset(x, y));
    }

    // Draw fill gradient
    if (points.length >= 2) {
      final fillPath = Path();
      fillPath.moveTo(points.first.dx, chartHeight + 5);
      for (final p in points) {
        fillPath.lineTo(p.dx, p.dy);
      }
      fillPath.lineTo(points.last.dx, chartHeight + 5);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF00D4FF).withValues(alpha: 0.3),
            const Color(0xFF00D4FF).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(leftPadding, 0, chartWidth, chartHeight + 5));
      canvas.drawPath(fillPath, fillPaint);
    }

    // Draw line
    final linePaint = Paint()
      ..color = const Color(0xFF00D4FF)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final linePath = Path();
    if (points.isNotEmpty) {
      linePath.moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        linePath.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(linePath, linePaint);

      // Draw dots
      final dotPaint = Paint()
        ..color = const Color(0xFF00D4FF)
        ..style = PaintingStyle.fill;
      for (final point in points) {
        canvas.drawCircle(point, 3.5, dotPaint);
      }
    }

    // Draw X-axis labels
    if (labels.isNotEmpty) {
      for (int i = 0; i < labels.length && i < dataPoints.length; i++) {
        final x = leftPadding + (i / (dataPoints.length - 1).clamp(1, double.infinity)) * chartWidth;
        final textPainter = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: const TextStyle(color: Colors.grey, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, size.height - labelHeight + 4),
        );
      }
    }
  }

  /// Totals per bar/point, worked out once (not on every repaint).
  late final List<double> _values = _getDataValues();

  List<double> _getDataValues() {
    final now = DateTime.now();
    final dataPoints = <double>[];

    switch (period) {
      case 'Day':
        // Today's 4-hour blocks, midnight first (matches the labels).
        for (int k = 0; k < 6; k++) {
          final hourExpenses = expenses.where((expense) {
            return expense.date.year == now.year &&
                expense.date.month == now.month &&
                expense.date.day == now.day &&
                expense.date.hour >= k * 4 &&
                expense.date.hour < k * 4 + 4;
          });
          dataPoints.add(hourExpenses.fold(0.0, (sum, expense) => sum + expense.amount));
        }
        break;
      case 'Week':
        // Each day of this calendar week, same as the Week total.
        final weekStart = _weekStartOf(now);
        for (int i = 0; i < 7; i++) {
          final date =
              DateTime(weekStart.year, weekStart.month, weekStart.day + i);
          final dayExpenses = expenses.where((expense) {
            return expense.date.year == date.year &&
                expense.date.month == date.month &&
                expense.date.day == date.day;
          });
          dataPoints.add(dayExpenses.fold(0.0, (sum, expense) => sum + expense.amount));
        }
        break;
      case 'Month':
        for (int i = 3; i >= 0; i--) {
          // The last 4 calendar weeks, oldest first, no overlap.
          final thisWeek = _weekStartOf(now);
          final weekStart = DateTime(
              thisWeek.year, thisWeek.month, thisWeek.day - 7 * i);
          final weekExpenses =
              expenses.where((expense) => _inWeek(expense.date, weekStart));
          dataPoints.add(weekExpenses.fold(0.0, (sum, expense) => sum + expense.amount));
        }
        break;
      case 'Year':
        for (int i = 5; i >= 0; i--) {
          final month = DateTime(now.year, now.month - i);
          final monthExpenses = expenses.where((expense) {
            return expense.date.year == month.year &&
                expense.date.month == month.month;
          });
          dataPoints.add(monthExpenses.fold(0.0, (sum, expense) => sum + expense.amount));
        }
        break;
      default:
        for (int i = 6; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final dayExpenses = expenses.where((expense) {
            return expense.date.year == date.year &&
                expense.date.month == date.month &&
                expense.date.day == date.day;
          });
          dataPoints.add(dayExpenses.fold(0.0, (sum, expense) => sum + expense.amount));
        }
    }

    return dataPoints;
  }

  @override
  bool shouldRepaint(covariant SpendingTrendPainter oldDelegate) {
    // A rebuild passes a new list even when nothing changed; compare the
    // numbers actually drawn.
    return oldDelegate.period != period ||
        !listEquals(oldDelegate.labels, labels) ||
        !listEquals(oldDelegate._values, _values);
  }
}

class _CategoryPieChartPainter extends CustomPainter {
  final Map<String, double> categoryTotals;
  final List<Color> colors;

  _CategoryPieChartPainter({required this.categoryTotals, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 3;
    final total = categoryTotals.values.fold(0.0, (sum, value) => sum + value);
    if (total == 0) return;

    double startAngle = -math.pi / 2;
    int colorIndex = 0;

    for (final entry in categoryTotals.entries) {
      final sweepAngle = (entry.value / total) * 2 * math.pi;
      final color = colorIndex < colors.length
          ? colors[colorIndex]
          : Colors.grey;

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      // Draw percentage label inside segment if large enough
      final percentage = (entry.value / total * 100);
      if (percentage >= 8) {
        final labelAngle = startAngle + sweepAngle / 2;
        final labelRadius = radius * 0.65;
        final labelX = center.dx + labelRadius * math.cos(labelAngle);
        final labelY = center.dy + labelRadius * math.sin(labelAngle);
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${percentage.toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(labelX - textPainter.width / 2, labelY - textPainter.height / 2),
        );
      }

      startAngle += sweepAngle;
      colorIndex++;
    }

    // Draw center circle for donut effect
    final centerPaint = Paint()
      ..color = const Color(0xFF0D0D0D)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.45, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _CategoryPieChartPainter oldDelegate) {
    return !mapEquals(oldDelegate.categoryTotals, categoryTotals) ||
        !listEquals(oldDelegate.colors, colors);
  }
}

class ComparisonBarPainter extends CustomPainter {
  final List<Expense> expenses;
  final String period;
  final List<String> labels;
  final String currency;

  ComparisonBarPainter({
    required this.expenses,
    required this.period,
    required this.labels,
    required this.currency,
  });

  /// Totals per bar, worked out once (not on every repaint).
  late final List<double> _values = _computeValues();

  List<double> _computeValues() {
    final now = DateTime.now();
    final data = <double>[];

    switch (period) {
      case 'Day':
        for (int i = 6; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final dayExpenses = expenses.where((expense) {
            return expense.date.year == date.year &&
                expense.date.month == date.month &&
                expense.date.day == date.day;
          });
          data.add(dayExpenses.fold(0.0, (sum, expense) => sum + expense.amount));
        }
        break;
      case 'Week':
        for (int i = 3; i >= 0; i--) {
          // The last 4 calendar weeks, oldest first, no overlap.
          final thisWeek = _weekStartOf(now);
          final weekStart = DateTime(
              thisWeek.year, thisWeek.month, thisWeek.day - 7 * i);
          final weekExpenses =
              expenses.where((expense) => _inWeek(expense.date, weekStart));
          data.add(weekExpenses.fold(0.0, (sum, expense) => sum + expense.amount));
        }
        break;
      case 'Month':
        for (int i = 5; i >= 0; i--) {
          final month = DateTime(now.year, now.month - i);
          final monthExpenses = expenses.where((expense) {
            return expense.date.year == month.year &&
                expense.date.month == month.month;
          });
          data.add(monthExpenses.fold(0.0, (sum, expense) => sum + expense.amount));
        }
        break;
      case 'Year':
        for (int i = 2; i >= 0; i--) {
          final year = now.year - i;
          final yearExpenses = expenses.where((expense) {
            return expense.date.year == year;
          });
          data.add(yearExpenses.fold(0.0, (sum, expense) => sum + expense.amount));
        }
        break;
      default:
        for (int i = 5; i >= 0; i--) {
          final month = DateTime(now.year, now.month - i);
          final monthExpenses = expenses.where((expense) {
            return expense.date.year == month.year &&
                expense.date.month == month.month;
          });
          data.add(monthExpenses.fold(0.0, (sum, expense) => sum + expense.amount));
        }
    }
    return data;
  }


  @override
  void paint(Canvas canvas, Size size) {
    const labelHeight = 22.0;
    const topPadding = 20.0;
    final chartHeight = size.height - labelHeight - topPadding;

    final data = _values;
    if (data.isEmpty) return;

    final maxValue = data.reduce(math.max);
    if (maxValue == 0) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'No spending data',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(size.width / 2 - textPainter.width / 2, size.height / 2 - textPainter.height / 2),
      );
      return;
    }

    final barWidth = size.width / data.length * 0.6;
    final spacing = size.width / data.length;

    for (int i = 0; i < data.length; i++) {
      final barHeight = (data[i] / maxValue) * chartHeight;
      final x = i * spacing + (spacing - barWidth) / 2;

      // Bar gradient
      final barRect = Rect.fromLTWH(x, topPadding + chartHeight - barHeight, barWidth, barHeight);
      final barPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF00D4FF), Color(0xFF0088AA)],
        ).createShader(barRect);
      
      final rRect = RRect.fromRectAndCorners(
        barRect,
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(rRect, barPaint);

      // Value label on top of bar
      if (data[i] > 0) {
        final valueLabel = compactAmount(data[i]);
        final textPainter = TextPainter(
          text: TextSpan(
            text: valueLabel,
            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(
            x + barWidth / 2 - textPainter.width / 2,
            topPadding + chartHeight - barHeight - textPainter.height - 4,
          ),
        );
      }

      // X-axis label
      if (i < labels.length) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: const TextStyle(color: Colors.grey, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        labelPainter.paint(
          canvas,
          Offset(
            x + barWidth / 2 - labelPainter.width / 2,
            size.height - labelHeight + 4,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ComparisonBarPainter oldDelegate) {
    return oldDelegate.period != period ||
        oldDelegate.currency != currency ||
        !listEquals(oldDelegate.labels, labels) ||
        !listEquals(oldDelegate._values, _values);
  }
}
