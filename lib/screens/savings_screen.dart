import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../services/app_prefs.dart';
import '../widgets/undo_snackbar.dart';
import 'settings_screen.dart';

const _teal = Color(0xFF26A69A);
final _inr = NumberFormat.decimalPattern('en_IN');

/// "₹1,25,000" (Indian grouping, no paise).
String _money(double v) => '₹${_inr.format(v.round())}';

/// Where month-end savings live: a total, this month so far, and every
/// closed month's Saved (or carried-over) leftover. Opened from the Savings
/// card on Categories and from Home.
class SavingsScreen extends StatelessWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Savings'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: ListenableBuilder(
        listenable: AppPrefs.instance,
        builder: (context, _) => Consumer<ExpenseProvider>(
          builder: (context, p, _) => _body(context, p),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ExpenseProvider p) {
    final now = DateTime.now();
    final history = p.savingsHistory;
    final saveMode = p.monthEndSavingsEnabled;
    final goal = AppPrefs.instance.savingsGoal;

    final savedMonths = history.where((m) => m.saved > 0).toList();
    final totalSaved = savedMonths.fold(0.0, (s, m) => s + m.saved);
    final yearSaved = savedMonths
        .where((m) => m.month.year == now.year)
        .fold(0.0, (s, m) => s + m.saved);
    final avg = savedMonths.isEmpty ? 0.0 : totalSaved / savedMonths.length;
    final lastCarry = history.where((m) => m.carried > 0).firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _hero(saveMode, totalSaved, savedMonths.length, yearSaved, avg,
            lastCarry),
        const SizedBox(height: 14),
        _ThisMonthCard(
          left: p.thisMonthLeft,
          carriedIn: p.thisMonthCarriedIn,
          saveMode: saveMode,
          goal: goal,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
          child: Row(
            children: [
              Text('HISTORY',
                  style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1)),
              const Spacer(),
              if (history.isNotEmpty)
                Text('Swipe a month to remove it',
                    style: TextStyle(color: Colors.grey[700], fontSize: 11.5)),
            ],
          ),
        ),
        if (history.isEmpty)
          _emptyHistory(saveMode)
        else
          for (final m in history) _MonthRow(month: m, goal: goal),
        const SizedBox(height: 20),
        _modeNote(context, saveMode),
      ],
    );
  }

  Widget _hero(bool saveMode, double total, int months, double year,
      double avg, MonthSavings? lastCarry) {
    final showCarry = total == 0 && lastCarry != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _teal.withValues(alpha: 0.35),
            const Color(0xFF0D2622),
          ],
        ),
        border: Border.all(color: _teal.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💰', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(showCarry ? 'CARRIED OVER' : 'TOTAL SAVED',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _money(showCarry ? lastCarry!.carried : total),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            showCarry
                ? 'Last month\'s leftover, now part of ${DateFormat('MMMM').format(DateTime(lastCarry!.month.year, lastCarry!.month.month + 1))}\'s income'
                : months == 0
                    ? 'Nothing saved yet'
                    : 'from $months month${months == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          if (!showCarry && months > 0) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _stat('This year', _money(year))),
                const SizedBox(width: 10),
                Expanded(child: _stat('Average / month', _money(avg))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _emptyHistory(bool saveMode) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(Icons.savings_outlined, size: 40, color: Colors.grey[600]),
            const SizedBox(height: 10),
            Text(
              saveMode
                  ? 'When a month ends, whatever is left of its income is saved here.'
                  : 'When a month ends, whatever is left is carried into the next month and listed here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13.5),
            ),
          ],
        ),
      );

  Widget _modeNote(BuildContext context, bool saveMode) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                const SettingsScreen(page: SettingsPage.optionalFeatures),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  saveMode
                      ? 'Leftovers go into "Saved" at month end. Change this or set a monthly goal in Optional features.'
                      : 'Leftovers carry into next month as income. Change this or set a monthly goal in Optional features.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey[700]),
            ],
          ),
        ),
      );
}

class _ThisMonthCard extends StatelessWidget {
  final double left;
  final double carriedIn;
  final bool saveMode;
  final double? goal;

  const _ThisMonthCard({
    required this.left,
    required this.carriedIn,
    required this.saveMode,
    required this.goal,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    final next = DateTime(now.year, now.month + 1, 1);
    final over = left < 0;
    final where = saveMode
        ? 'Goes into Saved on ${DateFormat('d MMM').format(monthEnd)}'
        : 'Carries into ${DateFormat('MMMM').format(next)} on 1 ${DateFormat('MMM').format(next)}';
    final double? progress =
        goal == null ? null : (left / goal!).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('THIS MONTH SO FAR',
                  style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.1)),
              const Spacer(),
              Text('${monthEnd.day - now.day + 1} days left',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            over ? 'Over by ${_money(-left)}' : _money(left),
            style: TextStyle(
              color: over ? Colors.redAccent : Colors.greenAccent,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            over ? 'Spending is above this month\'s income' : '$where if nothing changes',
            style: TextStyle(color: Colors.grey[500], fontSize: 12.5),
          ),
          if (carriedIn > 0) ...[
            const SizedBox(height: 4),
            Text('Includes ${_money(carriedIn)} carried over from last month',
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
          if (goal != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(
                    progress! >= 1 ? Colors.greenAccent : _teal),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              progress >= 1
                  ? 'Goal of ${_money(goal!)} reached 🎉'
                  : '${_money(left.clamp(0.0, goal!).toDouble())} of your ${_money(goal!)} goal',
              style: TextStyle(color: Colors.grey[400], fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  final MonthSavings month;
  final double? goal;
  const _MonthRow({required this.month, required this.goal});

  @override
  Widget build(BuildContext context) {
    final m = month;
    final isSaved = m.saved > 0;
    final double ratio =
        m.income > 0 ? (m.amount / m.income).clamp(0.0, 1.0).toDouble() : 0.0;
    final metGoal = goal != null && m.amount >= goal!;

    return Dismissible(
      key: ValueKey('savings-${m.month.year}-${m.month.month}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      // Delete here and let the list rebuild without the row (returning
      // false), so the Dismissible is never left dismissed in the tree.
      confirmDismiss: (_) async {
        await _remove(context);
        return false;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(DateFormat('MMM').format(m.month).toUpperCase(),
                      style: const TextStyle(
                          color: _teal,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  Text('${m.month.year}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(DateFormat('MMMM yyyy').format(m.month),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (metGoal) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified_rounded,
                            size: 15, color: Colors.greenAccent),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Income ${_money(m.income)} · Spent ${_money(m.spent)}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 4,
                      backgroundColor: Colors.grey.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation(_teal),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('+${_money(m.amount)}',
                    style: const TextStyle(
                        color: _teal,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  isSaved
                      ? '${(ratio * 100).round()}% saved'
                      : 'carried over',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(BuildContext context) async {
    final p = context.read<ExpenseProvider>();
    final label = DateFormat('MMMM').format(month.month);
    final saved = month.savedEntry;
    final carry = month.carryEntry;
    if (saved?.id != null) await p.deleteExpense(saved!.id!);
    if (carry?.id != null) await p.deleteIncome(carry!.id!);
    showUndo('Removed $label\'s ${saved != null ? 'savings' : 'carry-over'}',
        () async {
      if (saved != null) await p.restoreExpenses([saved]);
      if (carry != null) await p.restoreIncomes([carry]);
    });
  }
}

/// Compact Savings card shown at the top of Categories. Savings aren't
/// spending, so they're kept out of the category list and shown here.
class SavingsSummaryCard extends StatelessWidget {
  final FilterPeriod period;
  final DateTime? customStart;
  final DateTime? customEnd;

  const SavingsSummaryCard({
    super.key,
    required this.period,
    this.customStart,
    this.customEnd,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ExpenseProvider>();
    final now = DateTime.now();
    final saveMode = p.monthEndSavingsEnabled;
    final String title;
    final String amount;
    final String sub;

    if (period == FilterPeriod.monthly || period == FilterPeriod.weekly) {
      final left = p.thisMonthLeft;
      final next = DateTime(now.year, now.month + 1, 1);
      title = 'Left this month';
      amount = left < 0 ? '−${_money(-left)}' : _money(left);
      sub = left < 0
          ? 'Spending is above income'
          : saveMode
              ? 'Goes into Saved at month end'
              : 'Carries into ${DateFormat('MMMM').format(next)}';
    } else {
      final saved = p.savedInPeriod(period,
          customStart: customStart, customEnd: customEnd);
      final months = p.savedMonthsInPeriod(period,
          customStart: customStart, customEnd: customEnd);
      title = 'Saved';
      amount = _money(saved);
      sub = months == 0
          ? 'Nothing saved in this period yet'
          : 'from $months month${months == 1 ? '' : 's'}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SavingsScreen()),
          ),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [_teal.withValues(alpha: 0.28), const Color(0xFF0F1F1D)],
              ),
              border: Border.all(color: _teal.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                      child: Text('💰', style: TextStyle(fontSize: 28))),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(sub,
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 12.5)),
                    ],
                  ),
                ),
                Text(amount,
                    style: const TextStyle(
                        color: _teal,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
