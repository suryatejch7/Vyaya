import 'dart:ui';
import 'package:flutter/material.dart';
import 'savings_screen.dart';
import '../services/app_prefs.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/expense_models.dart';
import '../providers/expense_provider.dart';
import '../widgets/expense_card.dart';
import '../services/money_format.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  FilterPeriod _selectedPeriod = FilterPeriod.monthly;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String? _selectedAccountId; // null means all accounts

  String _getPeriodLabel() {
    switch (_selectedPeriod) {
      case FilterPeriod.weekly:
        return 'This Week';
      case FilterPeriod.monthly:
        return 'This Month';
      case FilterPeriod.yearly:
        return 'This Year';
      case FilterPeriod.allTime:
        return 'All Time';
      case FilterPeriod.custom:
        if (_customStartDate != null && _customEndDate != null) {
          final format = DateFormat('MMM d');
          return '${format.format(_customStartDate!)} - ${format.format(_customEndDate!)}';
        }
        return 'Custom Range';
    }
  }

  String _getFilterSummary(ExpenseProvider provider) {
    String periodLabel = _getPeriodLabel();
    if (_selectedAccountId != null) {
      final account = provider.getAccountById(_selectedAccountId!);
      if (account != null) {
        return '$periodLabel • ${account.name}';
      }
    }
    return periodLabel;
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // Keeps the sheet's top below the status bar / camera cutout.
      useSafeArea: true,
      builder: (context) => _FilterBottomSheet(
        currentPeriod: _selectedPeriod,
        customStartDate: _customStartDate,
        customEndDate: _customEndDate,
        currentAccountId: _selectedAccountId,
        onFilterSelected: (period, startDate, endDate, accountId) {
          setState(() {
            _selectedPeriod = period;
            _customStartDate = startDate;
            _customEndDate = endDate;
            _selectedAccountId = accountId;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  /// Anything other than "this month, all accounts".
  bool get _isFiltered =>
      _selectedPeriod != FilterPeriod.monthly || _selectedAccountId != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
      ),
      // Filter lives on the nav bar's row at the right, in the spot the
      // + button takes on Home.
      floatingActionButton: _FilterButton(
        active: _isFiltered,
        onPressed: _showFilterSheet,
      ),
      floatingActionButtonLocation: const _NavRowLocation(),
      floatingActionButtonAnimator: FloatingActionButtonAnimator.noAnimation,
      // Also listens to AppPrefs: "This week" follows the week-start setting.
      body: ListenableBuilder(
        listenable: AppPrefs.instance,
        builder: (context, _) => Consumer<ExpenseProvider>(
        builder: (context, expenseProvider, child) {
          final categoryTotals = expenseProvider.getCategoryTotalsByPeriod(
            _selectedPeriod,
            customStart: _customStartDate,
            customEnd: _customEndDate,
            accountId: _selectedAccountId,
          );
          final totalForPeriod = expenseProvider.getTotalByPeriod(
            _selectedPeriod,
            customStart: _customStartDate,
            customEnd: _customEndDate,
            accountId: _selectedAccountId,
          );

          // Savings aren't spending: they get their own card above the
          // categories (not per account, so hidden when filtering by one).
          final showSavings = _selectedAccountId == null;

          if (categoryTotals.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (showSavings)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: SavingsSummaryCard(
                        period: _selectedPeriod,
                        customStart: _customStartDate,
                        customEnd: _customEndDate,
                      ),
                    ),
                  const Icon(
                    Icons.category_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No expenses for ${_getPeriodLabel().toLowerCase()}',
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add some expenses to see category breakdown',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final sortedCategories = categoryTotals.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          return Column(
            children: [
              // Period summary header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getFilterSummary(expenseProvider),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '₹${formatAmount(totalForPeriod)}',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${sortedCategories.length} categories',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${expenseProvider.getExpensesByPeriodType(_selectedPeriod, customStart: _customStartDate, customEnd: _customEndDate, accountId: _selectedAccountId).length} expenses',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Categories list
              Expanded(
                child: ListView.builder(
                  // Room at the bottom so the last category can scroll
                  // above the nav bar and the filter button.
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                  itemCount: sortedCategories.length + (showSavings ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (showSavings && i == 0) {
                      return SavingsSummaryCard(
                        period: _selectedPeriod,
                        customStart: _customStartDate,
                        customEnd: _customEndDate,
                      );
                    }
                    final index = showSavings ? i - 1 : i;
                    final entry = sortedCategories[index];
                    final categoryName = entry.key;
                    final amount = entry.value;
                    final percentage = totalForPeriod > 0
                        ? (amount / totalForPeriod * 100)
                        : 0.0;

                    // Find the category object
                    final category = expenseProvider.categories.firstWhere(
                      (cat) => cat.name == categoryName,
                      orElse: () => ExpenseCategory(
                        id: categoryName,
                        name: categoryName,
                        icon: '📦',
                        colorHex: '#747D8C',
                      ),
                    );

                    // Budget logic (budgets are monthly, so only show for monthly view)
                    final budget = _selectedPeriod == FilterPeriod.monthly
                        ? expenseProvider.getCategoryBudget(categoryName)
                        : 0.0;
                    final isOverBudget =
                        _selectedPeriod == FilterPeriod.monthly &&
                        budget > 0 &&
                        amount > budget;
                    final budgetExcess = amount - budget;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => CategoryDetailScreen(
                                categoryName: categoryName,
                                filterPeriod: _selectedPeriod,
                                customStartDate: _customStartDate,
                                customEndDate: _customEndDate,
                                accountId: _selectedAccountId,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: isOverBudget
                                ? Border.all(color: Colors.red, width: 2)
                                : null,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: isOverBudget
                                            ? Colors.red.withValues(alpha: 0.2)
                                            : category.color.withValues(
                                                alpha: 0.2,
                                              ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Center(
                                        child: Text(
                                          category.icon,
                                          style: TextStyle(
                                            fontSize: 28,
                                            color: isOverBudget
                                                ? Colors.red
                                                : category.color,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  category.displayName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w600,
                                                    color: isOverBudget
                                                        ? Colors.red
                                                        : Colors.white,
                                                  ),
                                                ),
                                              ),
                                              if (isOverBudget) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'OVER',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '₹${formatAmount(amount)} • ${percentage.toStringAsFixed(1)}%',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                            ),
                                          ),
                                          if (budget > 0 &&
                                              _selectedPeriod ==
                                                  FilterPeriod.monthly) ...[
                                            const SizedBox(height: 8),
                                            LinearProgressIndicator(
                                              value: (amount / budget).clamp(
                                                0.0,
                                                1.0,
                                              ),
                                              backgroundColor: Colors.grey
                                                  .withValues(alpha: 0.3),
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    isOverBudget
                                                        ? Colors.red
                                                        : category.color,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Budget: ₹${formatAmount(budget, 0)}${isOverBudget ? ' (Over by ₹${formatAmount(budgetExcess, 0)})' : ''}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isOverBudget
                                                    ? Colors.red
                                                    : Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '₹${formatAmount(amount, 0)}',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: isOverBudget
                                                ? Colors.red
                                                : Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${expenseProvider.getExpensesByCategoryAndPeriod(categoryName, _selectedPeriod, customStart: _customStartDate, customEnd: _customEndDate, accountId: _selectedAccountId).length} items',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Bottom padding for nav bar
              const SizedBox(height: 100),
            ],
          );
        },
        ),
      ),
    );
  }
}

/// Puts a 56 dp button on the nav bar's row at the right: the bar sits 30 dp
/// up and is 63 dp tall, so its centre is 65 dp from the bottom.
class _NavRowLocation extends FloatingActionButtonLocation {
  const _NavRowLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry g) {
    final size = g.floatingActionButtonSize;
    return Offset(
      g.scaffoldSize.width - 16 - size.width,
      g.scaffoldSize.height - 65 - size.height / 2,
    );
  }
}

/// Round glass button matching the nav bar. A dot shows when a filter
/// other than "this month, all accounts" is on.
class _FilterButton extends StatelessWidget {
  final bool active;
  final VoidCallback onPressed;
  const _FilterButton({required this.active, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: 'Filter',
      child: GestureDetector(
        onTap: onPressed,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.15),
                          Colors.white.withValues(alpha: 0.08),
                        ],
                      ),
                      border: Border.all(
                        color: active
                            ? primary
                            : Colors.white.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(Icons.tune_rounded,
                          color: active ? primary : Colors.white, size: 24),
                    ),
                  ),
                ),
              ),
              if (active)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Filter Bottom Sheet Widget
class _FilterBottomSheet extends StatefulWidget {
  final FilterPeriod currentPeriod;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final String? currentAccountId;
  final Function(FilterPeriod, DateTime?, DateTime?, String?) onFilterSelected;

  const _FilterBottomSheet({
    required this.currentPeriod,
    required this.customStartDate,
    required this.customEndDate,
    required this.currentAccountId,
    required this.onFilterSelected,
  });

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late FilterPeriod _selectedPeriod;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _selectedPeriod = widget.currentPeriod;
    _startDate = widget.customStartDate;
    _endDate = widget.customEndDate;
    _selectedAccountId = widget.currentAccountId;
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 30)),
              end: DateTime.now(),
            ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Colors.black,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _selectedPeriod = FilterPeriod.custom;
      });
    }
  }

  static const _periods = [
    (FilterPeriod.weekly, 'This week'),
    (FilterPeriod.monthly, 'This month'),
    (FilterPeriod.yearly, 'This year'),
    (FilterPeriod.allTime, 'All time'),
  ];

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
      );

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: selected ? accent : Colors.grey),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? accent : Colors.white70,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      backgroundColor: const Color(0xFF232323),
      selectedColor: accent.withValues(alpha: 0.18),
      side: BorderSide(
        color: selected ? accent : Colors.grey.withValues(alpha: 0.25),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasRange = _startDate != null && _endDate != null;
    final isCustom = _selectedPeriod == FilterPeriod.custom;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 10, 20, 16 + MediaQuery.of(context).viewPadding.bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Filter',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                // Back to the default: this month, all accounts.
                TextButton(
                  onPressed: () => setState(() {
                    _selectedPeriod = FilterPeriod.monthly;
                    _selectedAccountId = null;
                  }),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _label('PERIOD'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (period, label) in _periods)
                  _chip(
                    label: label,
                    selected: _selectedPeriod == period,
                    onTap: () => setState(() => _selectedPeriod = period),
                  ),
                _chip(
                  icon: Icons.date_range,
                  label: isCustom && hasRange
                      ? '${DateFormat('d MMM').format(_startDate!)} – ${DateFormat('d MMM').format(_endDate!)}'
                      : 'Custom…',
                  selected: isCustom,
                  onTap: _selectDateRange,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _label('ACCOUNT'),
            Consumer<ExpenseProvider>(
              builder: (context, provider, _) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'All accounts',
                    selected: _selectedAccountId == null,
                    onTap: () => setState(() => _selectedAccountId = null),
                  ),
                  for (final account in provider.accounts)
                    _chip(
                      icon: Icons.account_balance_outlined,
                      label: account.name,
                      selected: _selectedAccountId == account.id,
                      onTap: () =>
                          setState(() => _selectedAccountId = account.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onFilterSelected(
                    _selectedPeriod,
                    _startDate,
                    _endDate,
                    _selectedAccountId,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Apply',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CategoryDetailScreen extends StatelessWidget {
  final String categoryName;
  final FilterPeriod filterPeriod;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final String? accountId;

  const CategoryDetailScreen({
    super.key,
    required this.categoryName,
    this.filterPeriod = FilterPeriod.monthly,
    this.customStartDate,
    this.customEndDate,
    this.accountId,
  });

  String _getPeriodLabel() {
    switch (filterPeriod) {
      case FilterPeriod.weekly:
        return 'This Week';
      case FilterPeriod.monthly:
        return 'This Month';
      case FilterPeriod.yearly:
        return 'This Year';
      case FilterPeriod.allTime:
        return 'All Time';
      case FilterPeriod.custom:
        if (customStartDate != null && customEndDate != null) {
          final s = customStartDate!, e = customEndDate!;
          // A whole calendar month (opened from Home) reads "August 2026".
          if (s.day == 1 &&
              e.year == s.year &&
              e.month == s.month &&
              e.day == DateTime(s.year, s.month + 1, 0).day) {
            return DateFormat('MMMM yyyy').format(s);
          }
          final format = DateFormat('MMM d');
          return '${format.format(customStartDate!)} - ${format.format(customEndDate!)}';
        }
        return 'Custom Range';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpenseProvider>(
      builder: (context, expenseProvider, child) {
        // Find the category object
        final category = expenseProvider.categories.firstWhere(
          (cat) => cat.name == categoryName,
          orElse: () => ExpenseCategory(
            id: categoryName,
            name: categoryName,
            icon: '📦',
            colorHex: '#747D8C',
          ),
        );

        final expenses = expenseProvider.getExpensesByCategoryAndPeriod(
          categoryName,
          filterPeriod,
          customStart: customStartDate,
          customEnd: customEndDate,
          accountId: accountId,
        );
        final totalAmount = expenses.fold(
          0.0,
          (sum, expense) => sum + expense.amount,
        );

        // Get account name for display if filtered
        String? accountName;
        if (accountId != null) {
          final account = expenseProvider.getAccountById(accountId!);
          accountName = account?.name;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(category.displayName),
            backgroundColor: category.color.withValues(alpha: 0.1),
          ),
          body: expenses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        category.icon,
                        style: TextStyle(
                          fontSize: 80,
                          color: category.color.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No ${category.displayName.toLowerCase()} expenses',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'for ${_getPeriodLabel().toLowerCase()}${accountName != null ? ' ($accountName)' : ''}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: category.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: category.color.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            category.icon,
                            style: TextStyle(
                              fontSize: 48,
                              color: category.color,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '₹${formatAmount(totalAmount)}',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: category.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${expenses.length} expense${expenses.length == 1 ? '' : 's'} • ${_getPeriodLabel()}${accountName != null ? ' • $accountName' : ''}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: expenses.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ExpenseCard(
                              expense: expenses[index],
                              currency: expenseProvider.currency,
                              category: category,
                              index: index,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
