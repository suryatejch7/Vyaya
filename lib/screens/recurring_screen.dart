import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense_models.dart';
import '../models/recurring_entry.dart';
import '../providers/expense_provider.dart';
import '../widgets/undo_snackbar.dart';

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

/// Lists monthly recurring expenses/income. Entries are created
/// automatically when due (checked whenever the app opens or resumes).
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Recurring'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RecurringFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, child) {
          final items = provider.recurringEntries;
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.repeat, size: 72, color: Colors.grey[700]),
                    const SizedBox(height: 16),
                    const Text(
                      'No recurring entries',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add things that repeat every month, like pocket money or subscriptions. They\'ll be logged automatically on their day.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 6),
            itemBuilder: (context, index) =>
                _RecurringTile(entry: items[index]),
          );
        },
      ),
    );
  }
}

class _RecurringTile extends StatelessWidget {
  final RecurringEntry entry;
  const _RecurringTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ExpenseProvider>();
    final currency = provider.currency;
    final category = provider.categories.firstWhere(
      (c) => c.name == entry.category,
      orElse: () => ExpenseCategory(
        id: entry.category,
        name: entry.category,
        icon: '📦',
        colorHex: '#747D8C',
      ),
    );
    final color = entry.isIncome ? Colors.green : category.color;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RecurringFormScreen(entry: entry),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: entry.isIncome
                      ? const Icon(Icons.arrow_downward_rounded,
                          color: Colors.green, size: 20)
                      : Text(category.icon,
                          style: const TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.isIncome ? '+' : ''}$currency${entry.amount.toStringAsFixed(0)} · ${entry.isIncome ? 'Income' : entry.category} · ${entry.scheduleLabel}',
                      style: TextStyle(
                        fontSize: 12,
                        color: entry.isIncome ? Colors.green[400] : color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.active
                          ? 'Next: ${DateFormat('d MMM yyyy').format(entry.nextDue)}'
                          : 'Paused',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Switch(
                value: entry.active,
                onChanged: (v) => provider.setRecurringActive(entry.id, v),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                onSelected: (value) {
                  if (value != 'delete') return;
                  final deleted = entry;
                  provider.deleteRecurring(entry.id);
                  showUndo(
                    '"${deleted.title}" deleted',
                    () => provider.addRecurring(deleted),
                  );
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Create / edit a recurring entry.
class RecurringFormScreen extends StatefulWidget {
  final RecurringEntry? entry;
  const RecurringFormScreen({super.key, this.entry});

  @override
  State<RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends State<RecurringFormScreen> {
  static const _noAccount = '__none__';

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _sourceController = TextEditingController();
  final _notesController = TextEditingController();

  RecurringType _type = RecurringType.expense;
  String _category = 'Other';
  RecurringFrequency _freq = RecurringFrequency.monthly;
  int _day = DateTime.now().day;
  int _weekday = DateTime.now().weekday;
  int _month = DateTime.now().month;
  String _accountId = _noAccount;
  bool _addThisMonth = false;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final provider = context.read<ExpenseProvider>();
    final e = widget.entry;
    if (e != null) {
      _type = e.type;
      _titleController.text = e.title;
      _amountController.text = e.amount.toStringAsFixed(
          e.amount == e.amount.roundToDouble() ? 0 : 2);
      _sourceController.text = e.source;
      _notesController.text = e.notes ?? '';
      _category = e.category;
      _freq = e.frequency;
      _day = e.dayOfMonth;
      _weekday = e.weekday;
      _month = e.month;
      _accountId = e.accountId ?? _noAccount;
    } else {
      if (provider.categories.isNotEmpty) {
        _category = provider.categories.first.name;
      }
      _accountId = provider.defaultAccount?.id ?? _noAccount;
    }
    // Keep dropdown values valid if a category/account was deleted.
    if (!provider.categories.any((c) => c.name == _category) &&
        provider.categories.isNotEmpty) {
      _category = provider.categories.first.name;
    }
    if (!provider.accounts.any((a) => a.id == _accountId)) {
      _accountId = _noAccount;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _sourceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// The schedule as currently set in the form (for date maths only).
  RecurringEntry get _schedule => RecurringEntry(
        id: '',
        type: _type,
        title: '',
        amount: 0,
        frequency: _freq,
        dayOfMonth: _day,
        weekday: _weekday,
        month: _month,
        nextDue: _today,
      );

  /// This week's / month's / year's occurrence.
  DateTime get _thisPeriodOccurrence => _schedule.occurrenceInPeriodOf(_today);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<ExpenseProvider>();
    final navigator = Navigator.of(context);
    final amount = double.parse(_amountController.text.trim());
    final accountId = _accountId == _noAccount ? null : _accountId;
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    if (_isEditing) {
      final old = widget.entry!;
      final sameSchedule = _freq == old.frequency &&
          _day == old.dayOfMonth &&
          _weekday == old.weekday &&
          _month == old.month;
      // Schedule changed: move the pending occurrence to the new day within
      // the same week / month / year it was due in (that period hasn't been
      // logged yet).
      final nextDue =
          sameSchedule ? old.nextDue : _schedule.occurrenceInPeriodOf(old.nextDue);
      await provider.updateRecurring(RecurringEntry(
        id: old.id,
        type: _type,
        title: _titleController.text.trim(),
        amount: amount,
        category: _category,
        source: _sourceController.text.trim(),
        frequency: _freq,
        dayOfMonth: _day,
        weekday: _weekday,
        month: _month,
        accountId: accountId,
        notes: notes,
        active: old.active,
        nextDue: nextDue,
      ));
    } else {
      final occ = _thisPeriodOccurrence;
      final nextDue = (occ.isAfter(_today) || _addThisMonth)
          ? occ
          : _schedule.nextAfter(occ);
      await provider.addRecurring(RecurringEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: _type,
        title: _titleController.text.trim(),
        amount: amount,
        category: _category,
        source: _sourceController.text.trim(),
        frequency: _freq,
        dayOfMonth: _day,
        weekday: _weekday,
        month: _month,
        accountId: accountId,
        notes: notes,
        nextDue: nextDue,
      ));
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final isIncome = _type == RecurringType.income;
    final showThisMonthSwitch =
        !_isEditing && !_thisPeriodOccurrence.isAfter(_today);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Recurring' : 'New Recurring'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: () async {
                final navigator = Navigator.of(context);
                await provider.deleteRecurring(widget.entry!.id);
                navigator.pop();
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<RecurringType>(
              segments: const [
                ButtonSegment(
                  value: RecurringType.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.arrow_upward_rounded),
                ),
                ButtonSegment(
                  value: RecurringType.income,
                  label: Text('Income'),
                  icon: Icon(Icons.arrow_downward_rounded),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: isIncome ? 'e.g., Pocket money' : 'e.g., Spotify',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '${provider.currency} ',
              ),
              validator: (v) {
                final a = double.tryParse(v?.trim() ?? '');
                return (a == null || a <= 0) ? 'Enter an amount' : null;
              },
            ),
            const SizedBox(height: 16),
            if (isIncome)
              TextFormField(
                controller: _sourceController,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Source (optional)',
                  hintText: 'e.g., Parents',
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: provider.categories
                        .any((c) => c.name == _category)
                    ? _category
                    : null,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in provider.categories)
                    DropdownMenuItem(
                      value: c.name,
                      child: Text('${c.icon}  ${c.name}'),
                    ),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
            const SizedBox(height: 16),
            const Text('Repeats',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<RecurringFrequency>(
              segments: const [
                ButtonSegment(
                    value: RecurringFrequency.weekly, label: Text('Weekly')),
                ButtonSegment(
                    value: RecurringFrequency.monthly, label: Text('Monthly')),
                ButtonSegment(
                    value: RecurringFrequency.yearly, label: Text('Yearly')),
              ],
              selected: {_freq},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _freq = s.first;
                _addThisMonth = false;
              }),
            ),
            const SizedBox(height: 12),
            if (_freq == RecurringFrequency.weekly)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    ChoiceChip(
                      label: Text(RecurringEntry.weekdayNames[d - 1]
                          .substring(0, 3)),
                      selected: _weekday == d,
                      showCheckmark: false,
                      onSelected: (_) => setState(() {
                        _weekday = d;
                        _addThisMonth = false;
                      }),
                      labelStyle: TextStyle(
                          color: _weekday == d ? Colors.black : Colors.white70),
                      selectedColor: Theme.of(context).colorScheme.primary,
                      backgroundColor: const Color(0xFF1A1A1A),
                      side: BorderSide.none,
                      shape: const StadiumBorder(),
                    ),
                ],
              )
            else
              Row(
                children: [
                  if (_freq == RecurringFrequency.yearly) ...[
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _month,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1E1E1E),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Month'),
                        items: [
                          for (var m = 1; m <= 12; m++)
                            DropdownMenuItem(
                                value: m,
                                child: Text(RecurringEntry.monthNames[m - 1])),
                        ],
                        onChanged: (v) => setState(() {
                          _month = v ?? _month;
                          _addThisMonth = false;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _day,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E1E1E),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: _freq == RecurringFrequency.yearly
                            ? 'Day'
                            : 'Day of month',
                        helperText: 'Shorter months use their last day',
                      ),
                      items: [
                        for (var d = 1; d <= 31; d++)
                          DropdownMenuItem(value: d, child: Text(_ordinal(d))),
                      ],
                      onChanged: (v) => setState(() {
                        _day = v ?? _day;
                        _addThisMonth = false;
                      }),
                    ),
                  ),
                ],
              ),
            if (provider.accounts.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  const DropdownMenuItem(
                    value: _noAccount,
                    child: Text('No account'),
                  ),
                  for (final a in provider.accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) =>
                    setState(() => _accountId = v ?? _noAccount),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (showThisMonthSwitch) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Also add ${_schedule.periodLabel}\'s entry now',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${DateFormat('EEE d MMM').format(_thisPeriodOccurrence)} has already come ${_schedule.periodLabel}. Leave off if you already logged it.',
                  style: const TextStyle(color: Colors.grey),
                ),
                value: _addThisMonth,
                onChanged: (v) => setState(() => _addThisMonth = v),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(_isEditing ? 'Save changes' : 'Add recurring'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
