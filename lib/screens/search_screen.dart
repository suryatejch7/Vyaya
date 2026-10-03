import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../models/expense_models.dart';
import '../widgets/expense_card.dart';
import '../widgets/income_card.dart';
import '../services/money_format.dart';

enum _SearchSort { newest, oldest, highest, lowest }

enum _SearchShow { all, expenses, income }

enum _SearchDate { any, week, month, last30, year, custom }

/// Everything the filter sheet can set. Immutable; the sheet edits a copy.
class _SearchFilters {
  final _SearchSort sort;
  final _SearchShow show;
  final String? accountId;
  final Set<String> categories; // empty = all
  final _SearchDate date;
  final DateTime? from;
  final DateTime? to;
  final double? minAmount;
  final double? maxAmount;

  const _SearchFilters({
    this.sort = _SearchSort.newest,
    this.show = _SearchShow.all,
    this.accountId,
    this.categories = const {},
    this.date = _SearchDate.any,
    this.from,
    this.to,
    this.minAmount,
    this.maxAmount,
  });

  /// Filters that narrow the results (sort order doesn't).
  bool get narrows =>
      show != _SearchShow.all ||
      accountId != null ||
      categories.isNotEmpty ||
      date != _SearchDate.any ||
      minAmount != null ||
      maxAmount != null;

  int get activeCount =>
      (sort != _SearchSort.newest ? 1 : 0) +
      (show != _SearchShow.all ? 1 : 0) +
      (accountId != null ? 1 : 0) +
      (categories.isNotEmpty ? 1 : 0) +
      (date != _SearchDate.any ? 1 : 0) +
      (minAmount != null || maxAmount != null ? 1 : 0);

  _SearchFilters copyWith({
    _SearchSort? sort,
    _SearchShow? show,
    String? Function()? accountId,
    Set<String>? categories,
    _SearchDate? date,
    DateTime? Function()? from,
    DateTime? Function()? to,
    double? Function()? minAmount,
    double? Function()? maxAmount,
  }) =>
      _SearchFilters(
        sort: sort ?? this.sort,
        show: show ?? this.show,
        accountId: accountId != null ? accountId() : this.accountId,
        categories: categories ?? this.categories,
        date: date ?? this.date,
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
        minAmount: minAmount != null ? minAmount() : this.minAmount,
        maxAmount: maxAmount != null ? maxAmount() : this.maxAmount,
      );

  bool matchesDate(DateTime d, DateTime now) {
    switch (date) {
      case _SearchDate.any:
        return true;
      case _SearchDate.week:
        return ExpenseProvider.dateInPeriod(d, FilterPeriod.weekly, now: now);
      case _SearchDate.month:
        return ExpenseProvider.dateInPeriod(d, FilterPeriod.monthly, now: now);
      case _SearchDate.year:
        return ExpenseProvider.dateInPeriod(d, FilterPeriod.yearly, now: now);
      case _SearchDate.last30:
        final start = DateTime(now.year, now.month, now.day - 29);
        return !d.isBefore(start);
      case _SearchDate.custom:
        return ExpenseProvider.dateInPeriod(d, FilterPeriod.custom,
            customStart: from, customEnd: to, now: now);
    }
  }

  bool matchesAmount(double a) =>
      (minAmount == null || a >= minAmount!) &&
      (maxAmount == null || a <= maxAmount!);
}

String _sortLabel(_SearchSort s) => switch (s) {
      _SearchSort.newest => 'Newest first',
      _SearchSort.oldest => 'Oldest first',
      _SearchSort.highest => 'Highest amount',
      _SearchSort.lowest => 'Lowest amount',
    };

String _showLabel(_SearchShow s) => switch (s) {
      _SearchShow.all => 'Everything',
      _SearchShow.expenses => 'Expenses',
      _SearchShow.income => 'Income',
    };

String _dateLabel(_SearchFilters f) {
  switch (f.date) {
    case _SearchDate.any:
      return 'Any time';
    case _SearchDate.week:
      return 'This week';
    case _SearchDate.month:
      return 'This month';
    case _SearchDate.last30:
      return 'Last 30 days';
    case _SearchDate.year:
      return 'This year';
    case _SearchDate.custom:
      if (f.from == null || f.to == null) return 'Custom…';
      final fmt = DateFormat('d MMM');
      return '${fmt.format(f.from!)} – ${fmt.format(f.to!)}';
  }
}

String _amt(double v) =>
    formatAmount(v, v == v.roundToDouble() ? 0 : 2);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  // Kept from initState: context lookups aren't allowed inside dispose().
  late final ExpenseProvider _provider;
  _SearchFilters _filters = const _SearchFilters();
  // The query is kept here (not in the provider) and applied 150 ms after
  // typing pauses, so each key press doesn't rebuild the whole app.
  String _query = '';
  Timer? _debounce;
  bool _showClear = false;

  static String _normalize(String v) =>
      v.trim().replaceAll(RegExp(r'\s+'), ' ');

  @override
  void initState() {
    super.initState();
    _provider = context.read<ExpenseProvider>();
    _controller.text = _provider.searchQuery;
    _query = _normalize(_controller.text);
    _showClear = _controller.text.isNotEmpty;
  }

  @override
  void dispose() {
    // Clear the query so it doesn't linger for the next search. No
    // notifyListeners here: the widget tree is locked during dispose.
    _debounce?.cancel();
    _provider.clearSearch(notify: false);
    _controller.dispose();
    super.dispose();
  }

  bool get _hasQuery => _query.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(child: _buildSearchField()),
                const SizedBox(width: 10),
                _buildFilterButton(),
              ],
            ),
          ),
          _buildActiveChips(),
          const SizedBox(height: 8),
          Expanded(
            child: Consumer<ExpenseProvider>(
              builder: (context, provider, child) =>
                  _buildResults(provider),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ top row

  Widget _buildSearchField() {
    return TextField(
      controller: _controller,
      autofocus: true,
      style: const TextStyle(color: Colors.white),
      onChanged: (value) {
        // Rebuild only when the clear button appears / disappears; results
        // update after the pause below.
        if (value.isNotEmpty != _showClear) {
          setState(() => _showClear = value.isNotEmpty);
        }
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _query = _normalize(value));
        });
      },
      decoration: InputDecoration(
        hintText: 'Payee, amount, category…',
        prefixIcon: const Icon(Icons.search, color: Colors.grey),
        suffixIcon: _showClear
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                onPressed: () {
                  _controller.clear();
                  _debounce?.cancel();
                  setState(() {
                    _query = '';
                    _showClear = false;
                  });
                },
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
      ),
    );
  }

  Widget _buildFilterButton() {
    final accent = Theme.of(context).colorScheme.primary;
    final n = _filters.activeCount;
    return Tooltip(
      message: 'Sort & filter',
      child: Material(
        color: n > 0 ? accent.withValues(alpha: 0.15) : const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: n > 0 ? BorderSide(color: accent) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openFilterSheet,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.tune_rounded, color: n > 0 ? accent : Colors.grey),
                if (n > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration:
                          BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: Text('$n',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Removable chips for each active filter, under the search bar.
  Widget _buildActiveChips() {
    final f = _filters;
    if (f.activeCount == 0) return const SizedBox.shrink();
    final chips = <Widget>[];
    void add(String label, _SearchFilters Function() clear) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InputChip(
          label: Text(label),
          onDeleted: () => setState(() => _filters = clear()),
          onPressed: _openFilterSheet,
          deleteIconColor: Colors.grey,
          backgroundColor: const Color(0xFF1F1F1F),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
          visualDensity: VisualDensity.compact,
        ),
      ));
    }

    if (f.sort != _SearchSort.newest) {
      add(_sortLabel(f.sort), () => f.copyWith(sort: _SearchSort.newest));
    }
    if (f.show != _SearchShow.all) {
      add('${_showLabel(f.show)} only',
          () => f.copyWith(show: _SearchShow.all));
    }
    if (f.accountId != null) {
      add(_provider.getAccountName(f.accountId),
          () => f.copyWith(accountId: () => null));
    }
    if (f.categories.isNotEmpty) {
      add(
          f.categories.length == 1
              ? f.categories.first
              : '${f.categories.length} categories',
          () => f.copyWith(categories: const {}));
    }
    if (f.date != _SearchDate.any) {
      add(_dateLabel(f), () => f.copyWith(date: _SearchDate.any));
    }
    if (f.minAmount != null || f.maxAmount != null) {
      final label = f.minAmount != null && f.maxAmount != null
          ? '₹${_amt(f.minAmount!)}–₹${_amt(f.maxAmount!)}'
          : f.minAmount != null
              ? '≥ ₹${_amt(f.minAmount!)}'
              : '≤ ₹${_amt(f.maxAmount!)}';
      add(label,
          () => f.copyWith(minAmount: () => null, maxAmount: () => null));
    }
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        children: chips,
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    FocusScope.of(context).unfocus();
    final result = await showModalBottomSheet<_SearchFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SearchFilterSheet(initial: _filters),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  // ------------------------------------------------------------ results

  Widget _buildResults(ExpenseProvider provider) {
    final f = _filters;
    if (!_hasQuery && !f.narrows) return _buildHint();

    final now = DateTime.now();
    // No text: browse everything that matches the filters.
    final expenses = f.show == _SearchShow.income
        ? const <Expense>[]
        : (_hasQuery ? provider.searchExpenses(_query) : provider.expenses)
            .where((e) =>
                (f.accountId == null || e.accountId == f.accountId) &&
                (f.categories.isEmpty ||
                    f.categories.contains(provider.categoryBucket(e.category))) &&
                f.matchesDate(e.date, now) &&
                f.matchesAmount(e.amount))
            .toList();
    // Incomes have no category, so a category filter shows expenses only.
    final incomes = f.show == _SearchShow.expenses || f.categories.isNotEmpty
        ? const <Income>[]
        : (_hasQuery ? provider.searchIncomes(_query) : provider.incomes)
            .where((i) =>
                (f.accountId == null || i.accountId == f.accountId) &&
                f.matchesDate(i.date, now) &&
                f.matchesAmount(i.amount))
            .toList();

    final results = <_Result>[
      for (final e in expenses) _Result.expense(e),
      for (final i in incomes) _Result.income(i),
    ];
    // Newest date first; same date -> most recently logged first.
    int newest(_Result a, _Result b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
    }

    results.sort((a, b) {
      switch (f.sort) {
        case _SearchSort.newest:
          return newest(a, b);
        case _SearchSort.oldest:
          return newest(b, a);
        case _SearchSort.highest:
          final c = b.amount.compareTo(a.amount);
          return c != 0 ? c : newest(a, b);
        case _SearchSort.lowest:
          final c = a.amount.compareTo(b.amount);
          return c != 0 ? c : newest(a, b);
      }
    });

    if (results.isEmpty) {
      // Scrolls when the keyboard leaves little room (small phones,
      // landscape) instead of overflowing.
      return const Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 80, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No results found',
                style: TextStyle(fontSize: 18, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Try other words or loosen the filters',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final currency = provider.currency;
    final spent = expenses
        .where((e) => !ExpenseProvider.isAutoSavedEntry(e))
        .fold(0.0, (s, e) => s + e.amount);
    // Carried-over leftovers aren't new money (same as the CSV totals).
    final received = incomes
        .where((i) => !ExpenseProvider.isCarryForwardEntry(i))
        .fold(0.0, (s, i) => s + i.amount);
    final summary = [
      '${results.length} result${results.length == 1 ? '' : 's'}',
      if (expenses.isNotEmpty) '$currency${formatAmount(spent, 0)} spent',
      if (incomes.isNotEmpty) '$currency${formatAmount(received, 0)} received',
    ].join(' · ');

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: results.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(summary,
                style: TextStyle(color: Colors.grey[500], fontSize: 12.5)),
          );
        }
        final r = results[index - 1];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: r.expense != null
              ? ExpenseCard(
                  expense: r.expense!,
                  currency: currency,
                  category: provider.categories.firstWhere(
                    (cat) => cat.name == r.expense!.category,
                    orElse: () => ExpenseCategory(
                      id: r.expense!.category,
                      name: r.expense!.category,
                      icon: '📦',
                      colorHex: '#747D8C',
                    ),
                  ),
                  index: index - 1,
                )
              : IncomeCard(
                  income: r.income!,
                  currency: currency,
                  index: index - 1,
                ),
        );
      },
    );
  }

  Widget _buildHint() {
    // Scrolls when the keyboard (open as soon as Search opens) leaves
    // little room, instead of overflowing.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Start typing to search',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'or pick filters to browse',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openFilterSheet,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Sort & filter'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the results: an expense or an income.
class _Result {
  final Expense? expense;
  final Income? income;
  _Result.expense(Expense e)
      : expense = e,
        income = null;
  _Result.income(Income i)
      : expense = null,
        income = i;

  DateTime get date => expense?.date ?? income!.date;
  DateTime get createdAt => expense?.createdAt ?? income!.createdAt;
  double get amount => expense?.amount ?? income!.amount;
}

// ============================================================ filter sheet

class _SearchFilterSheet extends StatefulWidget {
  final _SearchFilters initial;
  const _SearchFilterSheet({required this.initial});

  @override
  State<_SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<_SearchFilterSheet> {
  late _SearchFilters _f = widget.initial;
  late final TextEditingController _min = TextEditingController(
      text: widget.initial.minAmount == null
          ? ''
          : _amt(widget.initial.minAmount!));
  late final TextEditingController _max = TextEditingController(
      text: widget.initial.maxAmount == null
          ? ''
          : _amt(widget.initial.maxAmount!));

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Widget _label(String text, {String? note}) => Padding(
        padding: const EdgeInsets.only(left: 2, top: 18, bottom: 8),
        child: Row(
          children: [
            Text(
              text,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
            ),
            if (note != null) ...[
              const SizedBox(width: 8),
              Text(note,
                  style: TextStyle(color: Colors.grey[600], fontSize: 11.5)),
            ],
          ],
        ),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap,
      {IconData? icon}) {
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
          color: selected ? accent : Colors.grey.withValues(alpha: 0.25)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    );
  }

  Widget _wrap(List<Widget> children) =>
      Wrap(spacing: 8, runSpacing: 8, children: children);

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _f.from != null && _f.to != null
          ? DateTimeRange(start: _f.from!, end: _f.to!)
          : DateTimeRange(
              start: DateTime(now.year, now.month, now.day - 30), end: now),
    );
    if (picked != null) {
      setState(() => _f = _f.copyWith(
            date: _SearchDate.custom,
            from: () => picked.start,
            to: () => picked.end,
          ));
    }
  }

  void _apply() {
    double? parse(String s) {
      final v = double.tryParse(s.trim().replaceAll(',', '')); // "1,000"
      return (v == null || v < 0) ? null : v;
    }

    var min = parse(_min.text), max = parse(_max.text);
    if (min != null && max != null && min > max) {
      final t = min;
      min = max;
      max = t;
    }
    Navigator.pop(
        context, _f.copyWith(minAmount: () => min, maxAmount: () => max));
  }

  InputDecoration _amountDecoration(String label) => InputDecoration(
        labelText: label,
        prefixText: '₹ ',
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF232323),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ExpenseProvider>();
    final mq = MediaQuery.of(context);
    return Container(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + mq.viewPadding.bottom),
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
                const Text('Sort & filter',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _f = const _SearchFilters();
                    _min.clear();
                    _max.clear();
                  }),
                  child: const Text('Reset'),
                ),
              ],
            ),
            _label('SORT BY'),
            _wrap([
              for (final s in _SearchSort.values)
                _chip(_sortLabel(s), _f.sort == s,
                    () => setState(() => _f = _f.copyWith(sort: s))),
            ]),
            _label('SHOW'),
            _wrap([
              for (final s in _SearchShow.values)
                _chip(
                    _showLabel(s),
                    _f.show == s,
                    // Income has no category: picking it clears categories.
                    () => setState(() => _f = _f.copyWith(
                        show: s,
                        categories:
                            s == _SearchShow.income ? const {} : null))),
            ]),
            if (provider.accounts.isNotEmpty) ...[
              _label('ACCOUNT'),
              _wrap([
                _chip('All accounts', _f.accountId == null,
                    () => setState(() => _f = _f.copyWith(accountId: () => null)),
                    icon: Icons.account_balance_wallet_outlined),
                for (final a in provider.accounts)
                  _chip(
                      a.name,
                      _f.accountId == a.id,
                      () => setState(
                          () => _f = _f.copyWith(accountId: () => a.id)),
                      icon: Icons.account_balance_outlined),
              ]),
            ],
            if (_f.show != _SearchShow.income) ...[
              _label('CATEGORY',
                  note: _f.categories.isEmpty ? null : 'shows expenses only'),
              _wrap([
                _chip('All', _f.categories.isEmpty,
                    () => setState(() => _f = _f.copyWith(categories: const {}))),
                for (final c in provider.categories)
                  _chip('${c.icon} ${c.name}', _f.categories.contains(c.name),
                      () {
                    final next = Set<String>.from(_f.categories);
                    if (!next.remove(c.name)) next.add(c.name);
                    setState(() => _f = _f.copyWith(categories: next));
                  }),
              ]),
            ],
            _label('DATE'),
            _wrap([
              for (final d in _SearchDate.values)
                if (d != _SearchDate.custom)
                  _chip(_dateLabel(_f.copyWith(date: d)), _f.date == d,
                      () => setState(() => _f = _f.copyWith(date: d))),
              _chip(
                  _f.date == _SearchDate.custom
                      ? _dateLabel(_f)
                      : 'Custom…',
                  _f.date == _SearchDate.custom,
                  _pickRange,
                  icon: Icons.date_range),
            ]),
            _label('AMOUNT'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: _amountDecoration('Min'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('to', style: TextStyle(color: Colors.grey)),
                ),
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: _amountDecoration('Max'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Apply',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
