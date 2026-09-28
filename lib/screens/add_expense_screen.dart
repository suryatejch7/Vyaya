import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../providers/capture_provider.dart';
import '../services/app_prefs.dart';
import '../models/expense_models.dart';
// import '../models/transaction_ocr_models.dart'; // screenshot scanning off

class AddExpenseScreen extends StatefulWidget {
  final Expense? expense;
  final double? prefilledAmount;
  final String? prefilledPayee;
  final String? prefilledPaymentApp;
  final String? prefilledTransactionId;
  final String? prefilledCategory;
  final String? prefilledNotes;
  final DateTime? prefilledDate;
  final String? prefilledAccountId;
  final bool autoSave;
  // final ExtractedTransaction? extractedData; // screenshot scanning off

  const AddExpenseScreen({
    super.key,
    this.expense,
    this.prefilledAmount,
    this.prefilledPayee,
    this.prefilledPaymentApp,
    this.prefilledTransactionId,
    this.prefilledCategory,
    this.prefilledNotes,
    this.prefilledDate,
    this.prefilledAccountId,
    this.autoSave = false,
    // this.extractedData, // screenshot scanning off
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _payeeController = TextEditingController();
  final _noteController = TextEditingController();

  String _selectedCategory = 'Food';
  DateTime _selectedDate = DateTime.now();
  String? _selectedAccountId;
  bool _isInitialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    if (widget.expense != null) {
      _titleController.text = widget.expense!.description;
      _amountController.text = widget.expense!.amount.toString();
      _payeeController.text = widget.expense!.payee ?? '';
      _noteController.text = widget.expense!.notes ?? '';
      _selectedCategory = widget.expense!.category;
      _selectedDate = widget.expense!.date;
      _selectedAccountId = widget.expense!.accountId;
    } else {
      final prefs = AppPrefs.instance;
      _selectedDate = prefs.defaultEntryDate();
      // Optional feature: start from the last category / account used.
      if (prefs.rememberLastUsed) {
        final last = prefs.lastCategory;
        if (last != null && last.isNotEmpty) _selectedCategory = last;
        final lastAccount = prefs.lastAccountId;
        if (lastAccount != null && lastAccount.isNotEmpty) {
          _selectedAccountId = lastAccount;
        }
      }

      if (widget.prefilledAmount != null) {
        _amountController.text = widget.prefilledAmount!.toString();
      }

      if (widget.prefilledPayee != null && widget.prefilledPayee!.isNotEmpty) {
        _titleController.text = widget.prefilledPayee!;
      }

      if (widget.prefilledCategory != null &&
          widget.prefilledCategory!.isNotEmpty) {
        _selectedCategory = widget.prefilledCategory!;
      }

      if (widget.prefilledNotes != null && widget.prefilledNotes!.isNotEmpty) {
        _noteController.text = widget.prefilledNotes!;
      }

      if (widget.prefilledDate != null) {
        _selectedDate = widget.prefilledDate!;
      }

      if (widget.prefilledAccountId != null) {
        _selectedAccountId = widget.prefilledAccountId;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      final provider = context.read<ExpenseProvider>();
      // An account that no longer exists can't be shown by the dropdown.
      if (!provider.accounts.any((a) => a.id == _selectedAccountId)) {
        _selectedAccountId = null;
      }
      // Same for a remembered category that was deleted since.
      if (widget.expense == null &&
          widget.prefilledCategory == null &&
          provider.customCategories.isNotEmpty &&
          (_selectedCategory == ExpenseProvider.savedCategoryName ||
              !provider.customCategories
                  .any((c) => c.name == _selectedCategory))) {
        _selectedCategory = provider.customCategories
            .firstWhere((c) => c.name != ExpenseProvider.savedCategoryName,
                orElse: () => provider.customCategories.first)
            .name;
      }
      if (_selectedAccountId == null && provider.defaultAccount != null) {
        _selectedAccountId = provider.defaultAccount!.id;
      }

      if (widget.autoSave) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _saveExpense();
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _payeeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<ExpenseProvider>().currency;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.expense == null ? 'Add Expense' : 'Edit Expense'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAmountField(currency),
              const SizedBox(height: 20),

              _buildSectionTitle('DETAILS'),
              const SizedBox(height: 10),
              _buildTextField(
                controller: _titleController,
                labelText: 'Payee',
                hintText: 'e.g., Amazon, Swiggy',
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a payee';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _payeeController,
                labelText: 'Purpose (optional)',
                hintText: 'e.g., Groceries, Movie tickets',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 20),

              _buildSectionTitle('CATEGORY'),
              const SizedBox(height: 10),
              _buildCategorySelector(),
              const SizedBox(height: 20),

              _buildSectionTitle('DATE & ACCOUNT'),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildDateSelector()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildAccountSelector()),
                ],
              ),
              const SizedBox(height: 20),

              // Detected payments put the bank SMS text here.
              _buildSectionTitle('NOTES'),
              const SizedBox(height: 10),
              _buildTextField(
                controller: _noteController,
                labelText: 'Notes (optional)',
                hintText: 'Additional details...',
                maxLines: 3,
                minLines: 1,
              ),
              const SizedBox(height: 28),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveExpense,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Save Expense',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Small caps heading above each group of fields.
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  /// Big amount entry at the top: the one thing every entry needs.
  Widget _buildAmountField(String currency) {
    const big = TextStyle(fontSize: 34, fontWeight: FontWeight.bold);
    final accent = Theme.of(context).colorScheme.primary;
    final autoFocus = widget.expense == null &&
        widget.prefilledAmount == null &&
        AppPrefs.instance.autoFocusAmount;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('AMOUNT'),
          TextFormField(
            controller: _amountController,
            autofocus: autoFocus,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            cursorColor: accent,
            style: big.copyWith(color: Colors.white),
            decoration: InputDecoration(
              // prefixIcon (not prefixText) so the symbol shows even
              // before the field is focused.
              prefixIcon: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(currency, style: big.copyWith(color: accent)),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              hintText: '0',
              hintStyle: big.copyWith(color: Colors.grey[800]),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter an amount';
              }
              if (double.tryParse(value.trim()) == null) {
                return 'Please enter a valid amount';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    String? hintText,
    int maxLines = 1,
    int? minLines,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      validator: validator,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Consumer<ExpenseProvider>(
      builder: (context, provider, child) {
        // "Saved" is filled in by month-end savings, not picked by hand
        // (still shown when editing an entry that's already in it).
        final categories = provider.customCategories
            .where((c) =>
                c.name != ExpenseProvider.savedCategoryName ||
                _selectedCategory == c.name)
            .toList();

        return SizedBox(
          height: 96,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final isSelected = _selectedCategory == category.name;

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCategory = category.name;
                    });
                  },
                  child: Container(
                    width: 82,
                    height: 55,
                    decoration: BoxDecoration(
                      color: category.color,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          category.icon,
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          category.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// "Today", "Yesterday" or "28 Sep 2026".
  static String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _buildDateSelector() {
    return GestureDetector(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null && picked != _selectedDate) {
          setState(() {
            _selectedDate = picked;
          });
        }
      },
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _dateLabel(_selectedDate),
                style: const TextStyle(color: Colors.white, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSelector() {
    return Consumer<ExpenseProvider>(
      builder: (context, provider, child) {
        final accounts = provider.accounts;

        if (accounts.isEmpty) {
          return GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Add accounts in Settings first'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'No accounts',
                    style: TextStyle(
                      color: Colors.grey.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedAccountId,
              hint: const Text(
                'Select account',
                style: TextStyle(color: Colors.grey),
              ),
              dropdownColor: const Color(0xFF2A2A2A),
              icon: Icon(
                Icons.arrow_drop_down,
                color: Theme.of(context).colorScheme.primary,
              ),
              isExpanded: true,
              items: accounts.map((account) {
                return DropdownMenuItem<String>(
                  value: account.id,
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance,
                        color: account.isDefault
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          account.name,
                          style: const TextStyle(color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedAccountId = value;
                });
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveExpense() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSaving = true);

    try {
      final title = _titleController.text.trim();
      final amount = double.parse(_amountController.text.trim());
      final payee = _payeeController.text.trim().isEmpty
          ? null
          : _payeeController.text.trim();
      final now = DateTime.now();

      final expense = Expense(
        id: widget.expense?.id,
        description: title,
        amount: amount,
        category: _selectedCategory,
        date: _selectedDate,
        payee: payee,
        // Editing keeps the original tags: the transaction id links an
        // entry to its detected payment or month-end savings.
        paymentApp: widget.expense?.paymentApp ??
            widget.prefilledPaymentApp ??
            'Manual',
        transactionId:
            widget.expense?.transactionId ?? widget.prefilledTransactionId,
        notes: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        accountId: _selectedAccountId,
        createdAt: widget.expense?.createdAt ?? now,
        updatedAt: now,
      );

      final provider = context.read<ExpenseProvider>();
      final capture = context.read<CaptureProvider>();

      if (widget.expense != null) {
        await provider.updateExpense(expense);
        // Recategorised: teach auto-detect this payee's category.
        if (widget.expense!.category != expense.category) {
          await capture.learnFromEdit(
            expense.transactionId,
            expense.category,
            payee: expense.payee,
          );
        }
      } else {
        await provider.addExpense(expense);
        await AppPrefs.instance
            .rememberUsed(expense.category, expense.accountId);
      }

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        String errorMessage = 'Failed to save expense';
        if (e.toString().contains('validation')) {
          errorMessage = 'Please check your input and try again.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $errorMessage'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 1),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _saveExpense(),
            ),
          ),
        );
      }
    }
  }
}
