import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;
  static SharedPreferences? _prefs;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    _prefs = await SharedPreferences.getInstance();

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

  static Future<bool> areNotificationsEnabled() async {
    return _prefs?.getBool('notifications_enabled') ?? true;
  }

  static Future<void> setNotificationsEnabled(bool enabled) async {
    await _prefs?.setBool('notifications_enabled', enabled);
    if (!enabled) {
      await _notificationsPlugin.cancelAll();
    }
  }

  /// Alerts when this month's spending goes past this month's income.
  /// Skipped when no income is logged yet (nothing to compare against).
  static Future<void> checkIncomeExceeded(
    double monthlySpent,
    double monthlyIncome,
  ) async {
    if (!await areNotificationsEnabled()) return;
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

  static Future<void> checkCategoryBudgetExceeded(
    String categoryName,
    double categorySpent,
    double categoryBudget,
  ) async {
    if (!await areNotificationsEnabled()) return;
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
