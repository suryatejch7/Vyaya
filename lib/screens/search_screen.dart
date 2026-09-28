import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../models/expense_models.dart';
import '../widgets/expense_card.dart';
import '../widgets/income_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  // Kept from initState: context lookups aren't allowed inside dispose().
  late final ExpenseProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<ExpenseProvider>();
    _controller.text = _provider.searchQuery;
  }

  @override
  void dispose() {
    // Clear the query so it doesn't linger for the next search. No
    // notifyListeners here: the widget tree is locked during dispose.
    _provider.clearSearch(notify: false);
    _controller.dispose();
    super.dispose();
  }

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
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                context.read<ExpenseProvider>().setSearchQuery(value);
              },
              decoration: InputDecoration(
                hintText: 'Search expenses and income...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _controller.clear();
                          context.read<ExpenseProvider>().setSearchQuery('');
                          setState(() {});
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
            ),
          ),
          Expanded(
            child: Consumer<ExpenseProvider>(
              builder: (context, expenseProvider, child) {
                final expenses = expenseProvider.filteredExpenses;
                final incomes = expenseProvider.filteredIncomes;
                // Combine and sort by date (most recent first)
                final List<dynamic> combinedResults = [
                  ...expenses.map(
                    (e) => {'type': 'expense', 'data': e, 'date': e.date},
                  ),
                  ...incomes.map(
                    (i) => {'type': 'income', 'data': i, 'date': i.date},
                  ),
                ];
                combinedResults.sort(
                  (a, b) =>
                      (b['date'] as DateTime).compareTo(a['date'] as DateTime),
                );
                return _buildResultsContent(
                  combinedResults,
                  expenseProvider.currency,
                  expenseProvider.categories,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsContent(
    List<dynamic> results,
    String currency,
    List<ExpenseCategory> categories,
  ) {
    if (_controller.text.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Start typing to search',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Search expenses and income',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Try searching with different keywords',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        final isExpense = item['type'] == 'expense';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: isExpense
              ? ExpenseCard(
                  expense: item['data'] as Expense,
                  currency: currency,
                  category: categories.firstWhere(
                    (cat) => cat.name == (item['data'] as Expense).category,
                    orElse: () => ExpenseCategory(
                      id: (item['data'] as Expense).category,
                      name: (item['data'] as Expense).category,
                      icon: '📦',
                      colorHex: '#747D8C',
                    ),
                  ),
                  index: index,
                )
              : IncomeCard(
                  income: item['data'] as Income,
                  currency: currency,
                  index: index,
                ),
        );
      },
    );
  }
}
