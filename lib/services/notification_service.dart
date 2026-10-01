import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
// Switches now live in AppPrefs (Settings → Notifications).
// import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:vyaya_capture/vyaya_capture.dart';
import 'app_prefs.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;
  // static SharedPreferences? _prefs;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    // _prefs = await SharedPreferences.getInstance();

    // Scheduled notifications (daily reminder) need a time zone. Vyaya is
    // India-only, so IST is fixed rather than detected.
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(initializationSettings);

    await _requestPermissions();

    _isInitialized = true;
  }

  static Future<void> _requestPermissions() async {
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  /// The master switch in Settings → Notifications.
  static Future<bool> areNotificationsEnabled() async =>
      AppPrefs.instance.notificationsOn;

  /// Master switch: off clears everything scheduled; on puts back what the
  /// individual switches allow.
  static Future<void> setNotificationsEnabled(bool enabled) async {
    await AppPrefs.instance.setNotificationsOn(enabled);
    if (!enabled) await _notificationsPlugin.cancelAll();
    await syncDailyReminder(AppPrefs.instance.reminderMinutes);
    await onScheduledCleared?.call();
    await syncDetectedNotifier();
  }

  /// The native "New payment detected" notification follows its switch.
  static Future<void> syncDetectedNotifier() async {
    final p = AppPrefs.instance;
    try {
      await VyayaCapture.setNotifierEnabled(
          p.notificationsOn && p.detectedPaymentNotifications);
    } catch (e) {
      debugPrint('Detected-payment notifier switch failed: $e');
    }
  }

  // ==================== SCHEDULED (summaries, bills) ====================

  /// Schedules one notification at [at] (IST), replacing any with [id].
  /// [repeat] makes it recur (e.g. weekly on that weekday and time).
  /// Past times are skipped. Inexact, so it may arrive a few minutes late.
  static Future<void> scheduleAt(
    int id,
    String title,
    String body,
    DateTime at, {
    required String channelId,
    required String channelName,
    DateTimeComponents? repeat,
  }) async {
    try {
      // No cancel first: zonedSchedule with the same id replaces a pending
      // one, and cancel() would also clear one already in the tray.
      final when = tz.TZDateTime(
          tz.local, at.year, at.month, at.day, at.hour, at.minute);
      if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        when,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            icon: '@mipmap/ic_launcher',
            styleInformation: BigTextStyleInformation(body),
            visibility: _lockScreenVisibility,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: repeat,
      );
    } catch (e) {
      debugPrint('Scheduling $id failed: $e');
    }
  }

  /// Ids of notifications scheduled but not yet shown.
  /// Notifications with amounts follow the phone's lock-screen setting
  /// ("hide sensitive content" hides them); with App Lock on they stay off
  /// the lock screen entirely.
  static NotificationVisibility get _lockScreenVisibility =>
      AppPrefs.instance.appLockEnabled
          ? NotificationVisibility.secret
          : NotificationVisibility.private;

  static Future<Set<int>> pendingIds() async {
    try {
      final list = await _notificationsPlugin.pendingNotificationRequests();
      return list.map((r) => r.id).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Optional early warning: 80% of a limit or of this month's income.
  static Future<void> showNearLimit(String title, String body) async {
    if (!AppPrefs.instance.notificationsOn) return;
    await _showNotification(title, body);
  }

  // ==================== DAILY REMINDER ====================

  static const int _reminderId = 7001;

  /// Set by SmartNotifications to re-schedule summaries after a cancelAll.
  static Future<void> Function()? onScheduledCleared;

  /// Schedules (or cancels, when [minutes] is null) the daily "log your
  /// spending" reminder at [minutes] after midnight. Inexact, so Android
  /// may deliver it a few minutes late to save battery.
  ///
  /// [skipToday]: something was already logged today, so today's reminder
  /// is skipped and it starts again tomorrow.
  static Future<void> syncDailyReminder(int? minutes,
      {bool skipToday = false}) async {
    try {
      await _notificationsPlugin.cancel(_reminderId);
      if (minutes == null || !AppPrefs.instance.notificationsOn) return;
      final now = tz.TZDateTime.now(tz.local);
      var at = tz.TZDateTime(
          tz.local, now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
      if (!at.isAfter(now) || skipToday) at = at.add(const Duration(days: 1));
      await _notificationsPlugin.zonedSchedule(
        _reminderId,
        'Log today\'s spending',
        'Paid for anything Vyaya didn\'t catch? Add it before you forget.',
        at,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reminder',
            'Daily reminder',
            channelDescription: 'A daily nudge to log your expenses',
            icon: '@mipmap/ic_launcher',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Daily reminder scheduling failed: $e');
    }
  }

  /// Alerts when this month's spending goes past this month's income.
  /// Skipped when no income is logged yet (nothing to compare against).
  static Future<void> checkIncomeExceeded(
    double monthlySpent,
    double monthlyIncome, {
    bool test = false,
  }) async {
    final p = AppPrefs.instance;
    if (!test && !(p.notificationsOn && p.incomeAlerts)) return;
    if (monthlyIncome <= 0) return;

    if (monthlySpent > monthlyIncome) {
      final overspent = monthlySpent - monthlyIncome;
      await _showNotification(
        'Spending Exceeded Income',
        'You\'ve spent ₹${overspent.toInt()} more than your income this month. Income: ₹${monthlyIncome.toInt()}',
        importance: Importance.high,
      );
    }
  }

  /// Optional feature: a single expense at or above your chosen amount.
  static Future<void> showLargePayment(String payee, double amount) async {
    if (!AppPrefs.instance.notificationsOn) return;
    final id = 50000 + DateTime.now().millisecondsSinceEpoch % 40000;
    await _notificationsPlugin.show(
      id,
      'Large payment: ₹${amount.toStringAsFixed(0)}',
      payee.isEmpty ? 'Logged just now' : 'To $payee · logged just now',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'large_payments',
          'Large payments',
          channelDescription: 'Alerts for single payments above your limit',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          visibility: _lockScreenVisibility,
        ),
      ),
    );
  }

  static Future<void> checkCategoryBudgetExceeded(
    String categoryName,
    double categorySpent,
    double categoryBudget,
  ) async {
    final p = AppPrefs.instance;
    if (!(p.notificationsOn && p.categoryLimitAlerts)) return;
    if (categoryBudget <= 0) return;

    if (categorySpent >= categoryBudget) {
      final overspent = categorySpent - categoryBudget;
      await _showNotification(
        '$categoryName Budget Exceeded',
        'You\'ve exceeded your $categoryName budget by ₹${overspent.toInt()}. Budget: ₹${categoryBudget.toInt()}',
        importance: Importance.high,
      );
    }
  }

  static Future<void> _showNotification(
    String title,
    String body, {
    Importance importance = Importance.defaultImportance,
  }) async {
    final id = title.hashCode.abs() % 100000;
    await _notificationsPlugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'expense_tracker',
          'Vyaya Notifications',
          importance: importance,
          priority: _getPriorityFromImportance(importance),
          icon: '@mipmap/ic_launcher',
          visibility: _lockScreenVisibility,
        ),
      ),
    );
  }

  static Priority _getPriorityFromImportance(Importance importance) {
    switch (importance) {
      case Importance.max:
        return Priority.max;
      case Importance.high:
        return Priority.high;
      case Importance.defaultImportance:
        return Priority.defaultPriority;
      case Importance.low:
        return Priority.low;
      case Importance.min:
        return Priority.min;
      default:
        return Priority.defaultPriority;
    }
  }

  static Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }

  static Future<void> cancel(int id) async {
    await _notificationsPlugin.cancel(id);
  }
}
