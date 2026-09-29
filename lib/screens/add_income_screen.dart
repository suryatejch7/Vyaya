import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/expense_provider.dart';
import '../models/expense_models.dart';
import '../services/app_prefs.dart';

class AddIncomeScreen extends StatefulWidget {
  final Income? income; // For editing existing income

  const AddIncomeScreen({super.key, this.income});

  @override
  State<AddIncomeScreen> createState() => _AddIncomeScreenState();
}

class _AddIncomeScreenState extends State<AddIncomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _sourceController = TextEditingController();
  final _noteController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _selectedAccountId;
  bool _isInitialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    if (widget.income != null) {
      // Editing existing income
      _titleController.text = widget.income!.title;
      _amountController.text = widget.income!.amount.toString();
      _sourceController.text = widget.income!.source;
      _noteController.text = widget.income!.notes ?? '';
      _selectedDate = widget.income!.date;
      _selectedAccountId = widget.income!.accountId;
    } else {
      _selectedDate = AppPrefs.instance.defaultEntryDate();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize default account only once, synchronously during first build
    if (!_isInitialized) {
      _isInitialized = true;
      final provider = context.read<ExpenseProvider>();
      // An account that no longer exists can't be shown by the dropdown.
      if (!provider.accounts.any((a) => a.id == _selectedAccountId)) {
        _selectedAccountId = null;
      }
      if (_selectedAccountId == null && provider.defaultAccount != null) {
        _selectedAccountId = provider.defaultAccount!.id;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _sourceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.watch<ExpenseProvider>().currency;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.income == null ? 'Add Income' : 'Edit Income'),
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
              const SizedBox(height: 24),

              _buildSectionTitle('DETAILS'),
              const SizedBox(height: 10),
              _buildTextField(
                controller: _titleController,
                labelText: 'Title',
                hintText: 'e.g., Salary, Loan Repayment, Refund',
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _sourceController,
                labelText: 'From (optional)',
                hintText: 'e.g., Friend\'s name, Company, Amazon',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 24),

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
              const SizedBox(height: 24),

              _buildSectionTitle('NOTES'),
              const SizedBox(height: 10),
              _buildTextField(
                controller: _noteController,
                labelText: 'Notes (optional)',
                hintText: 'Additional details...',
                maxLines: 3,
                minLines: 1,
              ),
              const SizedBox(height: 32),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveIncome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    widget.income == null ? 'Add Income' : 'Update Income',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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
    final autoFocus =
        widget.income == null && AppPrefs.instance.autoFocusAmount;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionTitle('AMOUNT RECEIVED'),
              const Spacer(),
              const Icon(Icons.arrow_downward_rounded,
                  color: Colors.green, size: 16),
            ],
          ),
          TextFormField(
            controller: _amountController,
            autofocus: autoFocus,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            cursorColor: Colors.green,
            style: big.copyWith(color: Colors.white),
            decoration: InputDecoration(
              // prefixIcon (not prefixText) so the symbol shows even
              // before the field is focused.
              prefixIcon: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(currency, style: big.copyWith(color: Colors.green)),
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
              final amount = double.tryParse(value.trim());
              if (amount == null || !amount.isFinite) {
                return 'Please enter a valid amount';
              }
              if (amount <= 0) return 'Amount must be more than 0';
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
          borderSide: const BorderSide(color: Colors.green, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
      ),
    );
  }

  static String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('d MMM yyyy').format(d);
  }

  Widget _buildDateSelector() {
    return GestureDetector(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          // Widened for an entry already dated outside the range, which
          // would otherwise crash the picker.
          firstDate: _selectedDate.isBefore(DateTime(2020))
              ? _selectedDate
              : DateTime(2020),
          // Up to today, like expenses (a future date hid the entry).
          lastDate: _selectedDate.isAfter(DateTime.now())
              ? _selectedDate
              : DateTime.now(),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.dark(
                  primary: Colors.green,
                  onPrimary: Colors.white,
                  surface: const Color(0xFF1A1A1A),
                  onSurface: Colors.white,
                ),
              ),
              child: child!,
            );
          },
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
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Colors.green, size: 20),
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

        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedAccountId,
              isExpanded: true,
              dropdownColor: const Color(0xFF1A1A1A),
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.green),
              hint: Text(
                accounts.isEmpty ? 'No account' : 'Select account',
                style: const TextStyle(color: Colors.grey),
              ),
              items: accounts.map((account) {
                return DropdownMenuItem<String>(
                  value: account.id,
                  child: Text(
                    account.name,
                    style: const TextStyle(color: Colors.white),
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

  void _saveIncome() async {
    if (_isSaving) return;
    if (_formKey.currentState!.validate()) {
      // No account is fine (same as expenses): with none added yet, the
      // income is simply left unassigned.
      setState(() => _isSaving = true);

      final now = DateTime.now();

      final income = Income(
        id: widget.income?.id,
        amount: double.parse(_amountController.text.trim()),
        title: _titleController.text.trim(),
        source: _sourceController.text.trim(),
        date: _selectedDate,
        notes: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        accountId: _selectedAccountId,
        tag: widget.income?.tag,
        createdAt: widget.income?.createdAt ?? now,
        updatedAt: now,
      );

      final provider = context.read<ExpenseProvider>();

      try {
        if (widget.income == null) {
          await provider.addIncome(income);
        } else {
          await provider.updateIncome(income);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.income == null
                    ? 'Income added successfully!'
                    : 'Income updated successfully!',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
