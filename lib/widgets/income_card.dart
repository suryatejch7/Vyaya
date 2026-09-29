import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense_models.dart';
import '../providers/expense_provider.dart';
import 'undo_snackbar.dart';
import '../screens/add_income_screen.dart';
import '../services/money_format.dart';

class IncomeCard extends StatelessWidget {
  final Income income;
  final int index;
  final String currency;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectionTap;

  const IncomeCard({
    super.key,
    required this.income,
    required this.currency,
    this.index = 0,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onSelectionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (isSelectionMode) {
            onSelectionTap?.call();
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => AddIncomeScreen(income: income),
              ),
            );
          }
        },
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (isSelectionMode) ...[
                Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? Colors.green : Colors.grey,
                  size: 22,
                ),
                const SizedBox(width: 10),
              ],
              // Income icon — same box/metrics as ExpenseCard, green themed
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    color: Colors.green,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Income details (same structure as expense card)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      income.title,
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
                      'Income',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[400],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (income.source.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Source: ${income.source}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Amount and date column (same structure as expense card)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '+$currency${formatAmount(income.amount)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(income.date),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              // Delete menu - same as expense card
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteWithUndo(context);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
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

  String _formatDate(DateTime date) {
    // Compare calendar days, not 24h periods: 11pm yesterday is "Yesterday".
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final difference = today.difference(day).inDays;

    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference > 1 && difference < 7) {
      return '$difference days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  /// Deletes right away and offers UNDO for 5 seconds.
  void _deleteWithUndo(BuildContext context) {
    final provider = context.read<ExpenseProvider>();
    final deleted = income;
    if (income.id == null) return;
    provider.deleteIncome(income.id!);
    showUndo(
      '"${deleted.title}" deleted',
      () => provider.restoreIncomes([deleted]),
    );
  }
}
