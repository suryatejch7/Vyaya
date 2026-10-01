import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup_service.dart';

/// Shortcuts that can sit in the nav bar's swipe-up sheet. Two of the three
/// are shown there; the one left out is listed in Settings instead.
enum QuickShortcut { detected, lentBorrowed, recurring }

/// Settings → Optional features. Stored under `ls_opt_*` keys, so backups
/// carry them along. Values are read straight from SharedPreferences, so a
/// restore or reset is picked up on the next rebuild.
class AppPrefs extends ChangeNotifier {
  AppPrefs._();
  static final AppPrefs instance = AppPrefs._();

  static const String appVersion = '2.2.0';
  static const String releasesUrl =
      'https://github.com/suryatejch7/Vyaya/releases';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Re-applies stored values after a restore or reset: rebuilds listeners
  /// and re-schedules (or cancels) the daily reminder to match.
  Future<void> reloadAfterDataChange(
      Future<void> Function(int? minutes) syncReminder) async {
    await syncReminder(reminderMinutes);
    notifyListeners();
  }

  String? _get(String key) => _prefs?.getString('ls_opt_$key');

  Future<void> _set(String key, String value) async {
    await _prefs?.setString('ls_opt_$key', value);
    BackupService.autoSave();
    notifyListeners();
  }

  // ---- Week start (Sunday by default) ----

  bool get weekStartsMonday => _get('week_monday') == '1';
  Future<void> setWeekStartsMonday(bool v) => _set('week_monday', v ? '1' : '0');

  /// 00:00 on the first day of the week containing [d].
  DateTime weekStartOf(DateTime d) {
    final back = weekStartsMonday ? d.weekday - 1 : d.weekday % 7;
    return DateTime(d.year, d.month, d.day - back);
  }

  /// Short weekday names in week order (Sun..Sat or Mon..Sun).
  List<String> get weekdayLabels => weekStartsMonday
      ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
      : const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  // ---- Quick actions sheet ----

  /// The shortcut kept out of the swipe-up sheet (shown in Settings).
  /// Recurring by default.
  QuickShortcut get shortcutInSettings => QuickShortcut.values.firstWhere(
        (s) => s.name == _get('quick_in_settings'),
        orElse: () => QuickShortcut.recurring,
      );
  Future<void> setShortcutInSettings(QuickShortcut s) =>
      _set('quick_in_settings', s.name);

  /// The two shortcuts shown in the sheet, in a fixed order.
  List<QuickShortcut> get shortcutsInSheet => QuickShortcut.values
      .where((s) => s != shortcutInSettings)
      .toList();

  // ---- Hide totals on Home ----

  bool get hideHomeTotals => _get('hide_totals') == '1';
  Future<void> setHideHomeTotals(bool v) => _set('hide_totals', v ? '1' : '0');

  // ---- Open the keyboard on Add screens ----

  bool get autoFocusAmount => _get('autofocus_amount') == '1';
  Future<void> setAutoFocusAmount(bool v) =>
      _set('autofocus_amount', v ? '1' : '0');

  // ---- Daily reminder ----

  /// Minutes after midnight, or null when off.
  int? get reminderMinutes {
    final v = int.tryParse(_get('reminder') ?? '');
    return (v == null || v < 0) ? null : v;
  }

  Future<void> setReminderMinutes(int? minutes) =>
      _set('reminder', (minutes ?? -1).toString());

  // ---- Remember last category & account (Add Expense) ----

  bool get rememberLastUsed => _get('remember_last') == '1';
  Future<void> setRememberLastUsed(bool v) =>
      _set('remember_last', v ? '1' : '0');

  String? get lastCategory => _get('last_category');
  String? get lastAccountId => _get('last_account');

  /// Saved after every new expense, so turning the option on works at once.
  Future<void> rememberUsed(String category, String? accountId) async {
    await _prefs?.setString('ls_opt_last_category', category);
    await _prefs?.setString('ls_opt_last_account', accountId ?? '');
  }

  // ---- Remember category per payee (on by default) ----

  /// Adding an expense remembers the payee's category; typing that payee
  /// again picks it, and auto-detected payments to them get it too.
  bool get rememberPayeeCategory => _get('payee_category') != '0';
  Future<void> setRememberPayeeCategory(bool v) =>
      _set('payee_category', v ? '1' : '0');

  /// Keeps the remembered category after it's renamed or merged away.
  Future<void> renameLastCategory(String from, String to) async {
    if (lastCategory == from) {
      await _prefs?.setString('ls_opt_last_category', to);
    }
  }

  // ---- Suggest new categories (on by default) ----

  /// Offer to create a category (e.g. "Gym" for Nutrabay) when a payment
  /// clearly belongs to a kind you have no category for.
  bool get suggestNewCategories => _get('suggest_new_cat') != '0';

  /// Turning it back on also brings back suggestions you dismissed.
  Future<void> setSuggestNewCategories(bool v) async {
    if (v) await _prefs?.setString('ls_opt_dismissed_groups', '');
    await _set('suggest_new_cat', v ? '1' : '0');
  }

  /// Kinds ("fitness", "pets"…) you said to stop suggesting.
  Set<String> get dismissedGroups => (_get('dismissed_groups') ?? '')
      .split(',')
      .where((s) => s.isNotEmpty)
      .toSet();

  Future<void> dismissGroup(String key) => _set('dismissed_groups',
      ({...dismissedGroups, key}.toList()..sort()).join(','));

  // ---- Automation apps (MacroDroid / Tasker) ----

  /// Lets an ADD_EXPENSE intent with auto=true save without showing the
  /// screen. Off by default: any installed app can send that intent.
  bool get allowAutomationAutoSave => _get('intent_autosave') == '1';
  Future<void> setAllowAutomationAutoSave(bool v) =>
      _set('intent_autosave', v ? '1' : '0');

  // ---- Notifications (Settings → Notifications) ----

  /// Master switch: off means Vyaya shows no notifications at all.
  bool get notificationsOn => _get('notif_all') != '0';
  Future<void> setNotificationsOn(bool v) => _set('notif_all', v ? '1' : '0');

  /// Earlier versions had one "Spending alerts" switch for both alerts
  /// below; it's their starting value.
  bool get _legacySpendingAlerts =>
      _prefs?.getBool('notifications_enabled') ?? true;

  /// "Spent more than your income this month".
  bool get incomeAlerts {
    final v = _get('alert_income');
    return v == null ? _legacySpendingAlerts : v == '1';
  }

  Future<void> setIncomeAlerts(bool v) => _set('alert_income', v ? '1' : '0');

  /// "<Category> went over its limit".
  bool get categoryLimitAlerts {
    final v = _get('alert_category');
    return v == null ? _legacySpendingAlerts : v == '1';
  }

  Future<void> setCategoryLimitAlerts(bool v) =>
      _set('alert_category', v ? '1' : '0');

  /// "New payment detected" while Vyaya is closed.
  bool get detectedPaymentNotifications => _get('notif_detected') != '0';
  Future<void> setDetectedPaymentNotifications(bool v) =>
      _set('notif_detected', v ? '1' : '0');

  /// Plain weekly / monthly nudges when the app hasn't been opened (the
  /// summaries with numbers need the app to have run). Off by default.
  bool get inactivityNudges => _get('notif_nudges') == '1';
  Future<void> setInactivityNudges(bool v) =>
      _set('notif_nudges', v ? '1' : '0');

  // ---- Spending pace on Home ----

  bool get showSpendingPace => _get('pace') == '1';
  Future<void> setShowSpendingPace(bool v) => _set('pace', v ? '1' : '0');

  // ---- Monthly savings goal ----

  /// Amount you aim to have left each month, or null when not set.
  double? get savingsGoal {
    final v = double.tryParse(_get('savings_goal') ?? '');
    return (v == null || v <= 0) ? null : v;
  }

  Future<void> setSavingsGoal(double? v) =>
      _set('savings_goal', (v ?? 0).toString());

  // ---- Large payment alert ----

  /// Notify when a single expense is at least this much, or null when off.
  double? get largePaymentAlert {
    final v = double.tryParse(_get('large_alert') ?? '');
    return (v == null || v <= 0) ? null : v;
  }

  Future<void> setLargePaymentAlert(double? v) =>
      _set('large_alert', (v ?? 0).toString());

  // ---- Scheduled summaries & reminders ----

  /// Sunday-afternoon notification about last week's spending.
  bool get weeklySummary => _get('weekly_summary') == '1';
  Future<void> setWeeklySummary(bool v) =>
      _set('weekly_summary', v ? '1' : '0');

  /// Hour (24h) the weekly summary arrives on Sundays.
  static const int weeklySummaryHour = 13;

  /// Notification on the 1st recapping the month that just ended.
  bool get monthlyRecap => _get('monthly_recap') == '1';
  Future<void> setMonthlyRecap(bool v) => _set('monthly_recap', v ? '1' : '0');

  /// A heads-up the day before a recurring bill is added.
  bool get billReminders => _get('bill_reminders') == '1';
  Future<void> setBillReminders(bool v) =>
      _set('bill_reminders', v ? '1' : '0');

  /// Warn at 80% of a category limit or of this month's income.
  bool get earlyWarnings => _get('early_warnings') == '1';
  Future<void> setEarlyWarnings(bool v) =>
      _set('early_warnings', v ? '1' : '0');

  // ---- App lock (PIN) ----

  /// Salted SHA-256 of the PIN, or null when the lock is off.
  String? get pinHash {
    final v = _get('pin_hash');
    return (v == null || v.isEmpty) ? null : v;
  }

  /// App lock is switched off for now, so a PIN saved earlier is ignored.
  // bool get appLockEnabled => pinHash != null;
  bool get appLockEnabled => false;
  Future<void> setPinHash(String? hash) => _set('pin_hash', hash ?? '');

  // ---- Late-night entries count as yesterday ----

  /// Before this hour, new entries default to yesterday's date.
  static const int lateNightCutoffHour = 4;

  bool get lateNightIsYesterday => _get('late_night') == '1';
  Future<void> setLateNightIsYesterday(bool v) =>
      _set('late_night', v ? '1' : '0');

  /// Default date for a new entry: now, or 11:59 PM yesterday when it's
  /// past midnight but before [lateNightCutoffHour] and the option is on.
  DateTime defaultEntryDate([DateTime? clock]) {
    final now = clock ?? DateTime.now();
    if (lateNightIsYesterday && now.hour < lateNightCutoffHour) {
      return DateTime(now.year, now.month, now.day - 1, 23, 59);
    }
    return now;
  }
}
