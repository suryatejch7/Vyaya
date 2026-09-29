import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense_models.dart';
import '../widgets/undo_snackbar.dart';
import '../providers/expense_provider.dart';
import '../providers/capture_provider.dart';
import 'detected_payments_screen.dart';
import '../widgets/expense_card.dart';
import '../widgets/income_card.dart';
import '../widgets/category_summary.dart';
import '../services/app_prefs.dart';
import 'savings_screen.dart';
import '../services/money_format.dart';

enum RecentViewType { all, creditCard }

class DashboardScreen extends StatefulWidget {
  final void Function(bool isSelectionMode, int selectedCount, VoidCallback clearSelection, VoidCallback deleteSelected)? onSelectionChanged;

  const DashboardScreen({super.key, this.onSelectionChanged});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  RecentViewType _selectedViewType = RecentViewType.all;
  bool _isSelectionMode = false;
  final Set<String> _selectedExpenseIds = {};
  final Set<String> _selectedIncomeIds = {};

  int get _totalSelected => _selectedExpenseIds.length + _selectedIncomeIds.length;

  void _notifySelectionChanged() {
    widget.onSelectionChanged?.call(
      _isSelectionMode,
      _totalSelected,
      _clearSelection,
      _deleteSelected,
    );
  }

  void _toggleExpenseSelection(String id) {
    setState(() {
      if (_selectedExpenseIds.contains(id)) {
        _selectedExpenseIds.remove(id);
      } else {
        _selectedExpenseIds.add(id);
      }
      if (_totalSelected == 0) _isSelectionMode = false;
    });
    _notifySelectionChanged();
  }

  void _toggleIncomeSelection(String id) {
    setState(() {
      if (_selectedIncomeIds.contains(id)) {
        _selectedIncomeIds.remove(id);
      } else {
        _selectedIncomeIds.add(id);
      }
      if (_totalSelected == 0) _isSelectionMode = false;
    });
    _notifySelectionChanged();
  }

  void _startSelectionWithExpense(String id) {
    setState(() {
      _isSelectionMode = true;
      _selectedExpenseIds.add(id);
    });
    _notifySelectionChanged();
  }

  void _startSelectionWithIncome(String id) {
    setState(() {
      _isSelectionMode = true;
      _selectedIncomeIds.add(id);
    });
    _notifySelectionChanged();
  }

  void _clearSelection() {
    setState(() {
      _isSelectionMode = false;
      _selectedExpenseIds.clear();
      _selectedIncomeIds.clear();
    });
    _notifySelectionChanged();
  }

  /// Deletes the selection right away; the undo bar (5 s) replaces the old
  /// "Delete selected?" confirmation.
  Future<void> _deleteSelected() async {
    final total = _selectedExpenseIds.length + _selectedIncomeIds.length;
    if (total == 0) return;
    final provider = context.read<ExpenseProvider>();

    // Keep copies so UNDO can re-add them.
    final deletedExpenses = provider.expenses
        .where((e) => _selectedExpenseIds.contains(e.id))
        .toList();
    final deletedIncomes = provider.incomes
        .where((i) => _selectedIncomeIds.contains(i.id))
        .toList();
    final expenseIds = _selectedExpenseIds.toList();
    final incomeIds = _selectedIncomeIds.toList();
    _clearSelection();

    for (final id in expenseIds) {
      await provider.deleteExpense(id);
    }
    for (final id in incomeIds) {
      await provider.deleteIncome(id);
    }
    showUndo(
      'Deleted $total item${total > 1 ? 's' : ''}',
      () async {
        await provider.restoreExpenses(deletedExpenses);
        await provider.restoreIncomes(deletedIncomes);
      },
    );
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// ~200 at normal text size; grows with the pace line and font scale.
  double _headerHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final base = AppPrefs.instance.showSpendingPace ? 228.0 : 200.0;
    return (base + (scale - 1) * 150).clamp(base, 380.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          final expenseProvider = context.read<ExpenseProvider>();
          await expenseProvider.reloadExpenses();
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Header height follows its content: taller with the optional
            // pace line or a larger system font, so nothing gets clipped.
            ListenableBuilder(
              listenable: AppPrefs.instance,
              builder: (context, _) => SliverAppBar(
              expandedHeight: _headerHeight(context),
              pinned: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Expense Tracker',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 8),
                        TotalExpenseWidget(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ),
            // "N payments detected" banner (auto-detection review queue)
            SliverToBoxAdapter(
              child: Consumer<CaptureProvider>(
                builder: (context, cap, child) {
                  final n = cap.pendingCount;
                  if (n == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Material(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const DetectedPaymentsScreen(),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.bolt_rounded,
                                  color: Colors.amber),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      n == 1
                                          ? '1 payment detected'
                                          : '$n payments detected',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      'Tap to review',
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: CategorySummary(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildViewTypeSelector(),
              ),
            ),
            Consumer<ExpenseProvider>(
              builder: (context, expenseProvider, child) {
                return _buildTransactionsList(expenseProvider);
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildViewTypeSelector() {
    return Row(
      children: [
        PopupMenuButton<RecentViewType>(
          onSelected: (value) {
            setState(() {
              _selectedViewType = value;
            });
          },
          offset: const Offset(0, 40),
          color: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getViewTypeLabel(_selectedViewType),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.grey[400],
                size: 28,
              ),
            ],
          ),
          itemBuilder: (context) => [
            _buildPopupMenuItem(
              RecentViewType.all,
              'Recent Activity',
              Icons.swap_vert_rounded,
            ),
            _buildPopupMenuItem(
              RecentViewType.creditCard,
              'Credit Card Activity',
              Icons.credit_card_rounded,
            ),
          ],
        ),
        const Spacer(),
      ],
    );
  }

  PopupMenuItem<RecentViewType> _buildPopupMenuItem(
    RecentViewType type,
    String label,
    IconData icon,
  ) {
    final isSelected = _selectedViewType == type;
    return PopupMenuItem<RecentViewType>(
      value: type,
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected
                ? (type == RecentViewType.creditCard
                      ? Colors.orange
                      : Theme.of(context).colorScheme.primary)
                : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[300],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            Icon(
              Icons.check,
              color: type == RecentViewType.creditCard
                  ? Colors.orange
                  : Theme.of(context).colorScheme.primary,
              size: 18,
            ),
          ],
        ],
      ),
    );
  }

  String _getViewTypeLabel(RecentViewType type) {
    switch (type) {
      case RecentViewType.all:
        return 'Recent Activity';
      case RecentViewType.creditCard:
        return 'Credit Card';
    }
  }

  /// Build the transactions list based on selected view type
  Widget _buildTransactionsList(ExpenseProvider provider) {
    switch (_selectedViewType) {
      case RecentViewType.all:
        return _buildAllTransactionsList(provider);
      case RecentViewType.creditCard:
        return _buildCreditCardList(provider);
    }
  }

  Widget _buildExpensesList(ExpenseProvider provider) {
    final expenses = provider.expenses;

    if (expenses.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 80,
                color: Colors.grey[700],
              ),
              const SizedBox(height: 16),
              const Text(
                'No expenses found',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add your first expense by tapping the + button',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final currency = provider.currency;
    final categories = provider.categories;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final expense = expenses[index];
          final category = _findCategory(categories, expense.category);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ExpenseCard(
              key: ValueKey('expense_${expense.id}'),
              expense: expense,
              currency: currency,
              category: category,
              index: index,
              isSelectionMode: _isSelectionMode,
              isSelected: _selectedExpenseIds.contains(expense.id),
              onLongPress: () => _startSelectionWithExpense(expense.id!),
              onSelectionTap: () => _toggleExpenseSelection(expense.id!),
            ),
          );
        },
        childCount: expenses.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
      ),
    );
  }

  Widget _buildIncomesList(ExpenseProvider provider) {
    final incomes = provider.incomes;

    if (incomes.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 80,
                color: Colors.grey[700],
              ),
              const SizedBox(height: 16),
              const Text(
                'No income recorded',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add income by tapping the + button',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final currency = provider.currency;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final income = incomes[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: IncomeCard(
              key: ValueKey('income_${income.id}'),
              income: income,
              currency: currency,
              index: index,
              isSelectionMode: _isSelectionMode,
              isSelected: _selectedIncomeIds.contains(income.id),
              onLongPress: () => _startSelectionWithIncome(income.id!),
              onSelectionTap: () => _toggleIncomeSelection(income.id!),
            ),
          );
        },
        childCount: incomes.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
      ),
    );
  }

  Widget _buildAllTransactionsList(ExpenseProvider provider) {
    final expenses = provider.viewMonthExpenses;
    final incomes = provider.viewMonthIncomes;

    // Combine and sort by date (most recent first)
    final List<dynamic> allTransactions = [
      ...expenses.map((e) => {'type': 'expense', 'data': e, 'date': e.date}),
      ...incomes.map((i) => {'type': 'income', 'data': i, 'date': i.date}),
    ];
    DateTime loggedAt(Map t) => t['data'] is Expense
        ? (t['data'] as Expense).createdAt
        : (t['data'] as Income).createdAt;
    allTransactions.sort((a, b) {
      final c = (b['date'] as DateTime).compareTo(a['date'] as DateTime);
      return c != 0 ? c : loggedAt(b).compareTo(loggedAt(a));
    });

    if (allTransactions.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.swap_vert_rounded, size: 80, color: Colors.grey[700]),
              const SizedBox(height: 16),
              const Text(
                'No transactions yet',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add expenses or income by tapping the + button',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final currency = provider.currency;
    final categories = provider.categories;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final transaction = allTransactions[index];
          final isExpense = transaction['type'] == 'expense';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: isExpense
                ? ExpenseCard(
                    key: ValueKey('expense_${transaction['data'].id}'),
                    expense: transaction['data'],
                    currency: currency,
                    category: _findCategory(
                      categories,
                      (transaction['data'] as Expense).category,
                    ),
                    index: index,
                    isSelectionMode: _isSelectionMode,
                    isSelected: _selectedExpenseIds.contains(transaction['data'].id),
                    onLongPress: () => _startSelectionWithExpense(transaction['data'].id!),
                    onSelectionTap: () => _toggleExpenseSelection(transaction['data'].id!),
                  )
                : IncomeCard(
                    key: ValueKey('income_${transaction['data'].id}'),
                    income: transaction['data'],
                    currency: currency,
                    index: index,
                    isSelectionMode: _isSelectionMode,
                    isSelected: _selectedIncomeIds.contains(transaction['data'].id),
                    onLongPress: () => _startSelectionWithIncome(transaction['data'].id!),
                    onSelectionTap: () => _toggleIncomeSelection(transaction['data'].id!),
                  ),
          );
        },
        childCount: allTransactions.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
      ),
    );
  }

  Widget _buildCreditCardList(ExpenseProvider provider) {
    // Get all credit card account IDs
    final creditCardAccountIds = provider.accounts
        .where((a) => a.isCreditCard)
        .map((a) => a.id)
        .toSet();

    if (creditCardAccountIds.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.credit_card_off_rounded,
                size: 80,
                color: Colors.grey[700],
              ),
              const SizedBox(height: 16),
              const Text(
                'No credit cards added',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add a credit card account in Settings to track spending',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Filter expenses that are linked to credit card accounts
    // The automatic "Saved" entry isn't a card payment.
    final ccExpenses = provider.viewMonthExpenses
        .where((e) =>
            e.accountId != null &&
            creditCardAccountIds.contains(e.accountId) &&
            !ExpenseProvider.isAutoSavedEntry(e))
        .toList();

    if (ccExpenses.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.credit_card_rounded,
                size: 80,
                color: Colors.grey[700],
              ),
              const SizedBox(height: 16),
              const Text(
                'No credit card spending',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Expenses linked to your credit card accounts will appear here',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final currency = provider.currency;
    final categories = provider.categories;

    // Credit card total for the picked month (list is already filtered)
    final monthTotal = ccExpenses.fold(0.0, (sum, e) => sum + e.amount);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          // First item: summary card
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.withValues(alpha: 0.2),
                      Colors.deepOrange.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.credit_card_rounded,
                        color: Colors.orange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.isViewingCurrentMonth
                              ? 'This Month\'s CC Spending'
                              : 'CC Spending · ${DateFormat('MMM yyyy').format(provider.viewMonth)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Rebuilds when "Hide totals" is switched.
                        ListenableBuilder(
                          listenable: AppPrefs.instance,
                          builder: (context, _) => Text(
                            AppPrefs.instance.hideHomeTotals
                                ? '$currency••••'
                                : '$currency${formatAmount(monthTotal)}',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '${ccExpenses.length} txns',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Expense items (offset by 1 for summary card)
          final expense = ccExpenses[index - 1];
          final category = _findCategory(categories, expense.category);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ExpenseCard(
              key: ValueKey('cc_expense_${expense.id}'),
              expense: expense,
              currency: currency,
              category: category,
              index: index - 1,
              isSelectionMode: _isSelectionMode,
              isSelected: _selectedExpenseIds.contains(expense.id),
              onLongPress: () => _startSelectionWithExpense(expense.id!),
              onSelectionTap: () => _toggleExpenseSelection(expense.id!),
            ),
          );
        },
        childCount: ccExpenses.length + 1, // +1 for summary card
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
      ),
    );
  }


  ExpenseCategory _findCategory(
    List<ExpenseCategory> categories,
    String categoryName,
  ) {
    for (final cat in categories) {
      if (cat.name == categoryName) return cat;
    }
    return ExpenseCategory(
      id: categoryName,
      name: categoryName,
      icon: '📦',
      colorHex: '#747D8C',
    );
  }
}

class TotalExpenseWidget extends StatefulWidget {
  const TotalExpenseWidget({super.key});

  @override
  State<TotalExpenseWidget> createState() => _TotalExpenseWidgetState();
}

class _TotalExpenseWidgetState extends State<TotalExpenseWidget>
    with TickerProviderStateMixin {
  late AnimationController _numberController;
  late AnimationController _progressController;

  late Animation<double> _numberAnimation;
  late Animation<double> _progressAnimation;

  /// "Hide totals on Home" is on and you tapped the amount to show it.
  bool _peek = false;

  void _onPrefsChanged() {
    if (mounted) setState(() => _peek = false);
  }

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    AppPrefs.instance.addListener(_onPrefsChanged);
  }

  void _initializeAnimations() {
    _numberController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _progressController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _numberAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _numberController, curve: Curves.easeOutCubic),
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
    );

    // Start animations with a slight delay
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _numberController.forward();
        _progressController.forward();
      }
    });
  }

  @override
  void dispose() {
    AppPrefs.instance.removeListener(_onPrefsChanged);
    _numberController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpenseProvider>(
      builder: (context, expenseProvider, child) {
        final isOverBudget = expenseProvider.viewMonthOverspent; // spent > income
        final budgetExcess = expenseProvider.viewMonthOverspentBy;
        final totalIncome = expenseProvider.viewMonthIncome;
        final left = expenseProvider.viewMonthLeft;
        final totalExpense = expenseProvider.viewMonthTotalExpense;
        final isCurrent = expenseProvider.isViewingCurrentMonth;
        final currency = expenseProvider.currency;
        final canHide = AppPrefs.instance.hideHomeTotals;
        final hidden = canHide && !_peek;
        // Masks a figure while totals are hidden.
        String money(double v, int decimals) =>
            hidden ? '$currency••••' : '$currency${formatAmount(v, decimals)}';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month picker: ◀ label ▶ (▶ stops at the current month)
            Row(
              children: [
                _MonthArrow(
                  icon: Icons.chevron_left_rounded,
                  onTap: expenseProvider.previousViewMonth,
                ),
                const SizedBox(width: 2),
                // Shrinks with "…" instead of overflowing at large font sizes.
                Flexible(
                  child: Text(
                    isCurrent
                        ? 'This Month\'s Spending'
                        : 'Spent in ${DateFormat('MMMM yyyy').format(expenseProvider.viewMonth)}',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 2),
                _MonthArrow(
                  icon: Icons.chevron_right_rounded,
                  onTap: isCurrent ? null : expenseProvider.nextViewMonth,
                ),
              ],
            ),
            const SizedBox(height: 4),
            GestureDetector(
              // Tap the amount to show / hide it again.
              onTap: canHide ? () => setState(() => _peek = !_peek) : null,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Flexible(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _numberAnimation,
                      builder: (context, child) {
                        final animatedValue =
                            totalExpense * _numberAnimation.value;
                        // Shrinks instead of overflowing on narrow screens.
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                          money(animatedValue, 2),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isOverBudget
                                ? Colors.red
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        );
                      },
                    ),
                  ),
                  ),
                  if (isOverBudget) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        hidden ? 'Over' : '+$currency${formatAmount(budgetExcess, 0)} over',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  if (canHide) ...[
                    const SizedBox(width: 8),
                    Icon(
                      hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                  ],
                ],
              ),
            ),
            ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'Income: ${money(totalIncome, 0)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _leftLabel(
                    expenseProvider,
                    isCurrent: isCurrent,
                    isOver: isOverBudget,
                    excess: budgetExcess,
                    left: left,
                    money: money,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _progressAnimation,
                  builder: (context, child) {
                    final ratio = totalIncome > 0
                        ? totalExpense / totalIncome
                        : (totalExpense > 0 ? 1.0 : 0.0);
                    final progressValue =
                        ratio.clamp(0.0, 1.0) * _progressAnimation.value;
                    return LinearProgressIndicator(
                      value: progressValue,
                      backgroundColor: Colors.grey.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isOverBudget
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                      ),
                    );
                  },
                ),
              ),
            ],
            if (isCurrent && AppPrefs.instance.showSpendingPace)
              _buildPace(expenseProvider, left, totalIncome, money),
          ],
        );
      },
    );
  }

  /// Right side of the Income row: "₹X left" this month; for a closed month
  /// where the leftover went somewhere, "Saved ₹X" / "Carried ₹X" (tap for
  /// the Savings screen).
  Widget _leftLabel(
    ExpenseProvider p, {
    required bool isCurrent,
    required bool isOver,
    required double excess,
    required double left,
    required String Function(double, int) money,
  }) {
    if (isOver) {
      return Text('${money(excess, 0)} over',
          style: const TextStyle(
              fontSize: 14, color: Colors.red, fontWeight: FontWeight.w500));
    }
    final saved = isCurrent ? 0.0 : p.viewMonthSaved;
    final carried = isCurrent ? 0.0 : p.viewMonthCarriedOut;
    if (saved <= 0 && carried <= 0) {
      return Text('${money(left, 0)} left',
          style: const TextStyle(
              fontSize: 14, color: Colors.green, fontWeight: FontWeight.w500));
    }
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (context) => const SavingsScreen())),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('💰 ', style: TextStyle(fontSize: 13)),
          Text(
            saved > 0
                ? 'Saved ${money(saved, 0)}'
                : 'Carried over ${money(carried, 0)}',
            style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF26A69A),
                fontWeight: FontWeight.w600),
          ),
          const Icon(Icons.chevron_right, size: 16, color: Color(0xFF26A69A)),
        ],
      ),
    );
  }

  /// Optional "Today ₹X · ₹Y/day for N days" line under the progress bar.
  Widget _buildPace(ExpenseProvider provider, double left, double income,
      String Function(double, int) money) {
    final now = DateTime.now();
    final today = provider.expenses
        .where((e) =>
            e.date.year == now.year &&
            e.date.month == now.month &&
            e.date.day == now.day &&
            !ExpenseProvider.isAutoSavedEntry(e))
        .fold(0.0, (sum, e) => sum + e.amount);
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
    final String pace;
    if (income <= 0) {
      pace = 'Log income to see a daily budget';
    } else if (left <= 0) {
      pace = 'Nothing left to spend this month';
    } else {
      pace =
          '${money(left / daysLeft, 0)}/day for $daysLeft day${daysLeft == 1 ? '' : 's'}';
    }
    const style = TextStyle(fontSize: 12.5, color: Colors.grey);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text('Today ${money(today, 0)}', style: style),
          const SizedBox(width: 12),
          Expanded(
            child: Text(pace,
                style: style,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Compact chevron used by the home screen month picker.
class _MonthArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _MonthArrow({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          icon,
          size: 22,
          color: onTap == null ? Colors.grey[800] : Colors.grey[400],
        ),
      ),
    );
  }
}
