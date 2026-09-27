import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense_models.dart';
import '../providers/capture_provider.dart';
import '../providers/expense_provider.dart';
import '../services/capture/capture_models.dart';
import 'add_expense_screen.dart';

/// Review list for payments picked up from bank SMS / payment apps.
class DetectedPaymentsScreen extends StatelessWidget {
  const DetectedPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CaptureProvider>(
      builder: (context, cap, child) {
        final pending = cap.pending;
        final duplicates = cap.duplicates;
        final added = cap.added.take(30).toList();
        final dismissed = cap.dismissed.take(30).toList();

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text('Detected Payments'),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: [
              if (pending.length > 1)
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final n = pending.length;
                    await cap.acceptAll();
                    messenger.showSnackBar(
                      SnackBar(content: Text('Added $n payments')),
                    );
                  },
                  child: const Text('Add all'),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: cap.sync,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (!cap.isEnabled)
                  const _InfoCard(
                    icon: Icons.info_outline,
                    text:
                        'Auto-detection is off. Turn it on in Settings → Auto-detect Payments.',
                  ),
                _SectionHeader('To review', pending.length),
                if (pending.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'All caught up. New payments will show up here.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  for (final item in pending) _DetectedCard(item: item),
                if (duplicates.isNotEmpty)
                  _CollapsedSection(
                    title: 'Possibly already logged (${duplicates.length})',
                    subtitle:
                        'Matched an entry you added yourself, so they weren\'t added again',
                    children: [
                      for (final item in duplicates)
                        _CompactRow(
                          item: item,
                          actionLabel: 'Add anyway',
                          onAction: () => cap.restore(item.id),
                        ),
                    ],
                  ),
                if (added.isNotEmpty)
                  _CollapsedSection(
                    title: 'Recently added (${added.length})',
                    children: [
                      for (final item in added) _CompactRow(item: item),
                    ],
                  ),
                if (dismissed.isNotEmpty)
                  _CollapsedSection(
                    title: 'Dismissed (${dismissed.length})',
                    children: [
                      for (final item in dismissed)
                        _CompactRow(
                          item: item,
                          actionLabel: 'Restore',
                          onAction: () => cap.restore(item.id),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _when(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  final time = DateFormat('h:mm a').format(d);
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Yesterday, $time';
  return DateFormat('d MMM, h:mm a').format(d);
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader(this.title, this.count);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          count > 0 ? '$title ($count)' : title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );
}

const _flagText = {
  'transfer': 'Looks like a transfer between your own accounts',
  'reversal': 'Reversal of an earlier payment',
  'link': 'Message contains a link, so check it\'s genuine',
};

class _DetectedCard extends StatefulWidget {
  final DetectedTransaction item;
  const _DetectedCard({required this.item});

  @override
  State<_DetectedCard> createState() => _DetectedCardState();
}

class _DetectedCardState extends State<_DetectedCard> {
  bool _showRaw = false;

  ExpenseCategory _category(List<ExpenseCategory> categories, String name) =>
      categories.firstWhere(
        (c) => c.name == name,
        orElse: () => ExpenseCategory(
          id: name,
          name: name,
          icon: '📦',
          colorHex: '#747D8C',
        ),
      );

  Future<void> _pickCategory() async {
    final ep = context.read<ExpenseProvider>();
    final cap = context.read<CaptureProvider>();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (final c in ep.categories)
              ListTile(
                leading: Text(c.icon, style: const TextStyle(fontSize: 22)),
                title: Text(c.name, style: const TextStyle(color: Colors.white)),
                trailing: c.name == widget.item.category
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(context, c.name),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await cap.setCategory(widget.item.id, picked);
  }

  Future<void> _editAndAdd() async {
    final cap = context.read<CaptureProvider>();
    final item = widget.item;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(
          prefilledAmount: item.amount,
          prefilledPayee: item.merchant,
          prefilledPaymentApp: item.appLabel,
          prefilledTransactionId: 'cap-${item.id}',
          prefilledCategory: item.category,
          prefilledNotes: 'Auto-detected from ${item.appLabel}',
          prefilledDate: item.occurredAt,
        ),
      ),
    );
    if (saved == true) await cap.markAddedFromEditor(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ep = context.watch<ExpenseProvider>();
    final cap = context.read<CaptureProvider>();
    final currency = ep.currency;
    final category = _category(ep.categories, item.category);
    final color = item.isDebit ? category.color : Colors.green;
    final notes = <String>[
      for (final f in item.flags)
        if (_flagText.containsKey(f)) _flagText[f]!,
      if (item.fromImport) 'From SMS import',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: item.isDebit
                          ? Text(category.icon,
                              style: const TextStyle(fontSize: 20))
                          : const Icon(Icons.arrow_downward_rounded,
                              color: Colors.green, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
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
                          '${item.appLabel}${item.last4 != null ? ' ••${item.last4}' : ''} · ${_when(item.occurredAt)}',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${item.isDebit ? '' : '+'}$currency${item.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: item.isDebit ? Colors.white : Colors.green,
                    ),
                  ),
                ],
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final n in notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: 14, color: Colors.amber),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(n,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.amber)),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (item.isDebit)
                    ActionChip(
                      avatar: Text(category.icon),
                      label: Text(category.name),
                      onPressed: _pickCategory,
                    )
                  else
                    const Chip(label: Text('Income')),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _showRaw = !_showRaw),
                    child: Text(_showRaw ? 'Hide message' : 'Message'),
                  ),
                ],
              ),
              if (_showRaw)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    item.rawText,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => cap.dismiss(item.id),
                    child: const Text('Dismiss',
                        style: TextStyle(color: Colors.grey)),
                  ),
                  if (item.isDebit) ...[
                    const SizedBox(width: 4),
                    OutlinedButton(
                      onPressed: _editAndAdd,
                      child: const Text('Edit'),
                    ),
                  ],
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => cap.accept(item.id,
                        category: item.isDebit ? item.category : null),
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(item.isDebit ? 'Add' : 'Add income'),
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

class _CollapsedSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _CollapsedSection(
      {required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            title,
            style: const TextStyle(
                color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          subtitle: subtitle == null
              ? null
              : Text(subtitle!,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
          children: children,
        ),
      );
}

class _CompactRow extends StatelessWidget {
  final DetectedTransaction item;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _CompactRow({required this.item, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final currency = context.read<ExpenseProvider>().currency;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        item.title,
        style: const TextStyle(color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${item.appLabel} · ${_when(item.occurredAt)}',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${item.isDebit ? '' : '+'}$currency${item.amount.toStringAsFixed(0)}',
            style: TextStyle(
                color: item.isDebit ? Colors.white : Colors.green,
                fontWeight: FontWeight.w600),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
