import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../models/expense_models.dart';
import '../models/transaction_ocr_models.dart';

class AddExpenseScreen extends StatefulWidget {
  final Expense? expense;
  final double? prefilledAmount;
  final String? prefilledPayee;
  final String? prefilledPaymentApp;
  final String? prefilledTransactionId;
  final String? prefilledCategory;
  final String? prefilledNotes;
  final DateTime? prefilledDate;
  final bool autoSave;
  final ExtractedTransaction? extractedData;

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
    this.autoSave = false,
    this.extractedData,
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
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      final provider = context.read<ExpenseProvider>();
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
        title: const Text('Add Expense'),
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
              // Payee Field
              _buildSectionTitle('Payee'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _titleController,
                labelText: 'Payee',
                hintText: 'e.g., Amazon, Swiggy',
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a payee';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Amount Field
              _buildSectionTitle('Amount'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _amountController,
                labelText: 'Amount',
                hintText: '0.00',
                keyboardType: TextInputType.number,
                prefixText: '$currency ',
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Category Selector
              _buildSectionTitle('Category'),
              const SizedBox(height: 8),
              _buildCategorySelector(),
              const SizedBox(height: 20),

              // Date and Account Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle('Date'),
                        const SizedBox(height: 8),
                        _buildDateSelector(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle('Account'),
                        const SizedBox(height: 8),
                        _buildAccountSelector(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Purpose Field
              _buildSectionTitle('Purpose (Optional)'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _payeeController,
                labelText: 'Purpose',
                hintText: 'e.g., Groceries, Movie tickets',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 20),

              // Notes Field
              _buildSectionTitle('Notes (Optional)'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _noteController,
                labelText: 'Notes',
                hintText: 'Additional details...',
                maxLines: 1,
              ),
              const SizedBox(height: 24),

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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    String? hintText,
    TextInputType? keyboardType,
    String? prefixText,
    int maxLines = 1,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixText: prefixText,
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.grey),
        prefixStyle: const TextStyle(color: Colors.white),
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
        final categories = provider.customCategories;

        return SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final isSelected = _selectedCategory == category.name;

              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCategory = category.name;
                    });
                  },
                  child: Container(
                    width: 90,
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
                          style: const TextStyle(fontSize: 24),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
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
        paymentApp: widget.prefilledPaymentApp ?? 'PhonePe',
        transactionId: widget.prefilledTransactionId,
        notes: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        accountId: _selectedAccountId,
        createdAt: widget.expense?.createdAt ?? now,
        updatedAt: now,
      );

      final provider = context.read<ExpenseProvider>();

      if (widget.expense != null) {
        await provider.updateExpense(expense);
      } else {
        await provider.addExpense(expense);
      }

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        String errorMessage = 'Failed to save expense';
        if (e.toString().contains('network')) {
          errorMessage = 'Network error. Please check your connection.';
        } else if (e.toString().contains('database')) {
          errorMessage = 'Database error. Please try again.';
        } else if (e.toString().contains('validation')) {
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
