import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import '../models/expense_models.dart';
import '../models/recurring_entry.dart';
import '../providers/expense_provider.dart';
import 'app_prefs.dart';
import 'notification_service.dart';

/// Optional scheduled notifications (Settings → Optional features):
/// the Sunday weekly summary, the monthly recap on the 1st and bill
/// reminders the day before a recurring expense.
///
/// Notifications are scheduled ahead with their text filled in, so they're
/// re-scheduled (debounced) whenever your data or these settings change;
/// the numbers are always as of the last time the app saw your data.
class SmartNotifications {
  SmartNotifications._();

  static const _weeklyId = 7101; // next Sunday, with numbers
  static const _weeklyFallbackId = 7102; // repeats weekly if app unopened
  static const _monthlyId = 7201;
  static const _monthlyFallbackId = 7202;
  static const _billBase = 7300; // 7300..7339
  static const _billMax = 40;
  static const _billHour = 9;
  static const _recapHour = 10;

  static ExpenseProvider? _provider;
  static Timer? _debounce;
  static final _inr = NumberFormat.decimalPattern('en_IN');

  static String _money(double v) => '₹${_inr.format(v.round())}';

  /// Call once after the data is loaded.
  static void attach(ExpenseProvider provider) {
    if (_provider != null) return;
    _provider = provider;
    provider.addListener(_scheduleSoon);
    AppPrefs.instance.addListener(_scheduleSoon);
    NotificationService.onScheduledCleared = sync;
    _scheduleSoon();
  }

  static void _scheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), sync);
  }

  /// Cancels only if still scheduled, so one already in the tray stays.
  static Future<void> _cancelPending(int id, Set<int> pending) async {
    if (pending.contains(id)) await NotificationService.cancel(id);
  }

  static Future<void> sync() async {
    final p = _provider;
    if (p == null || p.userId == 0) return;
    try {
      final pending = await NotificationService.pendingIds();
      await _syncWeekly(p, pending);
      await _syncMonthly(p, pending);
      await _syncBills(p, pending);
    } catch (e) {
      debugPrint('Smart notifications sync failed: $e');
    }
  }

  // ---------------------------------------------------------------- weekly

  /// Next Sunday at [AppPrefs.weeklySummaryHour] (today if it's Sunday
  /// before that hour).
  @visibleForTesting
  static DateTime nextWeeklyTime(DateTime now) {
    var d = DateTime(now.year, now.month, now.day, AppPrefs.weeklySummaryHour);
    final daysAhead = (DateTime.sunday - now.weekday) % 7;
    d = DateTime(d.year, d.month, d.day + daysAhead, d.hour);
    if (!d.isAfter(now)) d = DateTime(d.year, d.month, d.day + 7, d.hour);
    return d;
  }

  /// Title and body for the 7 days before [sunday] (Sun–Sat).
  @visibleForTesting
  static (String, String) weeklyText(
      List<Expense> expenses, DateTime sunday, String Function(String) bucket) {
    final end = DateTime(sunday.year, sunday.month, sunday.day);
    final start = DateTime(end.year, end.month, end.day - 7);
    final prevStart = DateTime(start.year, start.month, start.day - 7);
    bool inRange(DateTime d, DateTime a, DateTime b) =>
        !d.isBefore(a) && d.isBefore(b);

    final week = expenses
        .where((e) =>
            !ExpenseProvider.isAutoSavedEntry(e) && inRange(e.date, start, end))
        .toList();
    final prev = expenses
        .where((e) =>
            !ExpenseProvider.isAutoSavedEntry(e) &&
            inRange(e.date, prevStart, start))
        .fold(0.0, (s, e) => s + e.amount);

    if (week.isEmpty) {
      return (
        'Your week in Vyaya',
        'No spending logged last week. Paid for anything? Add it so your totals stay right.'
      );
    }
    final total = week.fold(0.0, (s, e) => s + e.amount);
    final byCat = <String, double>{};
    for (final e in week) {
      final k = bucket(e.category);
      byCat[k] = (byCat[k] ?? 0) + e.amount;
    }
    final top = byCat.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final parts = <String>[
      '${week.length} payment${week.length == 1 ? '' : 's'}',
      'most on ${top.key} (${_money(top.value)})',
    ];
    if (prev > 0) {
      final pct = ((total - prev) / prev * 100).round();
      if (pct == 0) {
        parts.add('same as the week before');
      } else {
        parts.add('${pct > 0 ? '↑' : '↓'}${pct.abs()}% vs the week before');
      }
    }
    return ('Last week: ${_money(total)} spent', parts.join(' · '));
  }

  static Future<void> _syncWeekly(ExpenseProvider p, Set<int> pending) async {
    if (!AppPrefs.instance.weeklySummary) {
      await _cancelPending(_weeklyId, pending);
      await _cancelPending(_weeklyFallbackId, pending);
      return;
    }
    final at = nextWeeklyTime(DateTime.now());
    final (title, body) = weeklyText(p.expenses, at, p.categoryBucket);
    await NotificationService.scheduleAt(_weeklyId, title, body, at,
        channelId: 'weekly_summary', channelName: 'Weekly summary');
    // If the app isn't opened for a while, a plain weekly nudge still comes.
    await NotificationService.scheduleAt(
      _weeklyFallbackId,
      'Your week in Vyaya',
      'See how last week went: open Vyaya for your spending summary.',
      DateTime(at.year, at.month, at.day + 7, at.hour),
      channelId: 'weekly_summary',
      channelName: 'Weekly summary',
      repeat: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  // --------------------------------------------------------------- monthly

  static Future<void> _syncMonthly(ExpenseProvider p, Set<int> pending) async {
    if (!AppPrefs.instance.monthlyRecap) {
      await _cancelPending(_monthlyId, pending);
      await _cancelPending(_monthlyFallbackId, pending);
      return;
    }
    final now = DateTime.now();
    // Early on the 1st (before the recap hour) the recap still due today is
    // for the month that just ended; otherwise it's this month's, due on
    // the 1st of next month.
    final dueToday = now.day == 1 && now.hour < _recapHour;
    final m = dueToday
        ? DateTime(now.year, now.month - 1)
        : DateTime(now.year, now.month);
    final at = DateTime(m.year, m.month + 1, 1, _recapHour);
    final month = DateFormat('MMMM').format(m);
    bool inMonth(DateTime d) => d.year == m.year && d.month == m.month;
    final spent = p.expenses
        .where((e) => inMonth(e.date) && !ExpenseProvider.isAutoSavedEntry(e))
        .fold(0.0, (s, e) => s + e.amount);
    final income = p.incomes
        .where((i) => inMonth(i.date))
        .fold(0.0, (s, i) => s + i.amount);
    final left = income - spent;
    final String body;
    if (income <= 0) {
      body = 'You spent ${_money(spent)}. Log your income to see what\'s left each month.';
    } else if (left < 0) {
      body = 'Spent ${_money(spent)} of ${_money(income)} income, ${_money(-left)} over.';
    } else {
      final goal = AppPrefs.instance.savingsGoal;
      final where = p.monthEndSavingsEnabled ? 'saved' : 'carried over';
      body = 'Spent ${_money(spent)} of ${_money(income)} income, ${_money(left)} $where'
          '${goal == null ? '.' : left >= goal ? ' 🎉 goal reached.' : ' (goal ${_money(goal)}).'}';
    }
    await NotificationService.scheduleAt(
        _monthlyId, '$month recap', body, at,
        channelId: 'monthly_recap', channelName: 'Monthly recap');
    await NotificationService.scheduleAt(
      _monthlyFallbackId,
      'Your monthly recap',
      'A new month started: open Vyaya to see how last month went.',
      DateTime(at.year, at.month + 1, 1, _recapHour),
      channelId: 'monthly_recap',
      channelName: 'Monthly recap',
      repeat: DateTimeComponents.dayOfMonthAndTime,
    );
  }

  // ----------------------------------------------------------------- bills

  static Future<void> _syncBills(ExpenseProvider p, Set<int> pending) async {
    for (var i = 0; i < _billMax; i++) {
      await _cancelPending(_billBase + i, pending);
    }
    if (!AppPrefs.instance.billReminders) return;
    final now = DateTime.now();
    final due = p.recurringEntries
        .where((r) => r.active && r.type == RecurringType.expense)
        .toList()
      ..sort((a, b) => a.nextDue.compareTo(b.nextDue));
    var slot = 0;
    for (final r in due) {
      if (slot >= _billMax) break;
      final d = r.nextDue;
      final at = DateTime(d.year, d.month, d.day - 1, _billHour);
      if (!at.isAfter(now)) continue;
      await NotificationService.scheduleAt(
        _billBase + slot++,
        '${r.title} · ${_money(r.amount)} due tomorrow',
        'Recurring ${r.category} payment. Vyaya adds it on ${DateFormat('d MMM').format(d)}; make sure it\'s paid.',
        at,
        channelId: 'bill_reminders',
        channelName: 'Bill reminders',
      );
    }
  }
}
