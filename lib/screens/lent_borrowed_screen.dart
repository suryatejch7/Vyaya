import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/debt_entry.dart';
import '../providers/expense_provider.dart';
import '../widgets/undo_snackbar.dart';

/// Money lent to / borrowed from friends. Kept separate from expenses and
/// income so it never changes your spending totals.
class LentBorrowedScreen extends StatelessWidget {
  const LentBorrowedScreen({super.key});

  static void openForm(BuildContext context, {DebtEntry? entry}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DebtFormSheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Lent & Borrowed'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, child) {
          final currency = provider.currency;
          final all = provider.debts;
          final open = all.where((d) => !d.settled).toList();
          final settled = all.where((d) => d.settled).toList();
          final balances = provider.debtBalances.entries.toList()
            ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      label: 'You\'ll get',
                      amount: '$currency${provider.totalOwedToYou.toStringAsFixed(0)}',
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      label: 'You owe',
                      amount: '$currency${provider.totalYouOwe.toStringAsFixed(0)}',
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
              if (balances.isNotEmpty) ...[
                const SizedBox(height: 24),
                const _SectionTitle('By person'),
                const SizedBox(height: 8),
                for (final b in balances)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: (b.value > 0
                                      ? Colors.green
                                      : Colors.redAccent)
                                  .withValues(alpha: 0.2),
                              child: Text(
                                b.key.isNotEmpty ? b.key[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: b.value > 0
                                      ? Colors.green
                                      : Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                b.key,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              b.value > 0
                                  ? 'owes you $currency${b.value.toStringAsFixed(0)}'
                                  : 'you owe $currency${(-b.value).toStringAsFixed(0)}',
                              style: TextStyle(
                                color: b.value > 0
                                    ? Colors.green
                                    : Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              const _SectionTitle('Open'),
              const SizedBox(height: 8),
              if (open.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Nothing pending. Tap Add to log money you lent or borrowed.',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                for (final d in open) _DebtTile(entry: d),
              if (settled.isNotEmpty) ...[
                const SizedBox(height: 16),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Settled (${settled.length})',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    children: [for (final d in settled) _DebtTile(entry: d)],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String amount;
  final Color color;
  const _SummaryCard(
      {required this.label, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            amount,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  final DebtEntry entry;
  const _DebtTile({required this.entry});

  /// Settling asks whether to log the money that changed hands.
  Future<void> _settle(BuildContext context, ExpenseProvider provider) async {
    final currency = provider.currency;
    final amount = '$currency${entry.amount.toStringAsFixed(0)}';
    final primary = Theme.of(context).colorScheme.primary;
    final choice = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.isLent
                      ? '${entry.person} paid you back $amount?'
                      : 'You paid ${entry.person} back $amount?',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                  entry.isLent
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: primary),
              title: Text(
                  entry.isLent
                      ? 'Settle and add $amount as income'
                      : 'Settle and add $amount as an expense',
                  style: const TextStyle(color: Colors.white)),
              subtitle: const Text('Logged today on your default account',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline,
                  color: Colors.white70),
              title: const Text('Just mark as settled',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Already logged it, or it was not money',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () => Navigator.pop(context, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await provider.setDebtSettled(entry.id, true, record: choice);
    showUndo(
      choice
          ? 'Settled · ${entry.isLent ? 'income' : 'expense'} added'
          : 'Marked as settled',
      () => provider.setDebtSettled(entry.id, false),
    );
  }

  Future<void> _reopen(BuildContext context, ExpenseProvider provider) async {
    await provider.setDebtSettled(entry.id, false);
    showUndo(
      entry.settlementEntryId != null
          ? 'Reopened · recorded ${entry.isLent ? 'income' : 'expense'} removed'
          : 'Reopened',
      () => provider.setDebtSettled(entry.id, true,
          record: entry.settlementEntryId != null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ExpenseProvider>();
    final currency = provider.currency;
    final color = entry.isLent ? Colors.green : Colors.redAccent;
    final muted = entry.settled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => LentBorrowedScreen.openForm(context, entry: entry),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: muted ? 0.08 : 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    entry.isLent ? Icons.north_east : Icons.south_west,
                    color: muted ? Colors.grey : color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.person,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: muted ? Colors.grey : Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.isLent ? 'You lent' : 'You borrowed'} · ${DateFormat('d MMM yyyy').format(entry.date)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      if (entry.note != null && entry.note!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          entry.note!,
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '$currency${entry.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: muted ? Colors.grey : color,
                    decoration: muted ? TextDecoration.lineThrough : null,
                  ),
                ),
                IconButton(
                  tooltip: entry.settled ? 'Mark as open' : 'Mark as settled',
                  icon: Icon(
                    entry.settled
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: entry.settled ? Colors.green : Colors.grey,
                  ),
                  onPressed: () => entry.settled
                      ? _reopen(context, provider)
                      : _settle(context, provider),
                ),
                PopupMenuButton<String>(
                  icon:
                      const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                  onSelected: (value) {
                    if (value != 'delete') return;
                    final deleted = entry;
                    provider.deleteDebt(entry.id);
                    showUndo(
                      'Entry for ${deleted.person} deleted',
                      () => provider.addDebt(deleted),
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
      ),
    );
  }
}

/// Bottom sheet to add / edit a lent-or-borrowed entry.
class DebtFormSheet extends StatefulWidget {
  final DebtEntry? entry;
  const DebtFormSheet({super.key, this.entry});

  @override
  State<DebtFormSheet> createState() => _DebtFormSheetState();
}

class _DebtFormSheetState extends State<DebtFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _personController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isLent = true;
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    if (e != null) {
      _isLent = e.isLent;
      _personController.text = e.person;
      _amountController.text = e.amount.toStringAsFixed(
          e.amount == e.amount.roundToDouble() ? 0 : 2);
      _noteController.text = e.note ?? '';
      _date = e.date;
    }
  }

  @override
  void dispose() {
    _personController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<ExpenseProvider>();
    final navigator = Navigator.of(context);
    final note =
        _noteController.text.trim().isEmpty ? null : _noteController.text.trim();
    final amount = double.parse(_amountController.text.trim());
    final e = widget.entry;
    if (e == null) {
      await provider.addDebt(DebtEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        person: _personController.text.trim(),
        amount: amount,
        isLent: _isLent,
        date: _date,
        note: note,
      ));
    } else {
      await provider.updateDebt(DebtEntry(
        id: e.id,
        person: _personController.text.trim(),
        amount: amount,
        isLent: _isLent,
        date: _date,
        note: note,
        settled: e.settled,
        settledAt: e.settledAt,
        settlementEntryId: e.settlementEntryId,
      ));
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ExpenseProvider>();
    final people = provider.debtPeople;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.entry == null ? 'Add entry' : 'Edit entry',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('I lent'),
                    icon: Icon(Icons.north_east),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('I borrowed'),
                    icon: Icon(Icons.south_west),
                  ),
                ],
                selected: {_isLent},
                onSelectionChanged: (s) => setState(() => _isLent = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _personController,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Person'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              if (people.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in people.take(8))
                      ActionChip(
                        label: Text(p),
                        onPressed: () =>
                            setState(() => _personController.text = p),
                      ),
                  ],
                ),
              ],
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
              TextFormField(
                controller: _noteController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g., Dinner split',
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today, color: Colors.grey),
                title: Text(
                  DateFormat('d MMM yyyy').format(_date),
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: const Text('Change'),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(widget.entry == null ? 'Add' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
