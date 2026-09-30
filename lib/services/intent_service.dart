import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../screens/add_expense_screen.dart';
import 'app_prefs.dart';

class IntentService {
  static const MethodChannel _channel = MethodChannel('com.vyaya/intent');
  static BuildContext? _context;
  static bool _isInitialized = false;

  static void setContext(BuildContext context) {
    _context = context;
    if (!_isInitialized) {
      _initialize();
    }
  }

  static void _initialize() {
    _isInitialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onExpenseIntent') {
        if (call.arguments != null) {
          _handleExpenseIntent(Map<String, dynamic>.from(call.arguments));
        }
      }
    });

    // Check initial intent
    _getInitialIntent();
  }

  static Future<void> _getInitialIntent() async {
    try {
      final initialData = await _channel.invokeMethod('getInitialIntent');
      if (initialData != null) {
        _handleExpenseIntent(Map<String, dynamic>.from(initialData));
      }
    } catch (e) {
      debugPrint('Failed to get initial intent: $e');
    }
  }

  static void _handleExpenseIntent(Map<String, dynamic> data) {
    if (_context == null) return;

    // Extract fields
    final amountStr = data['amount']?.toString();
    final payeeStr = data['payee']?.toString() ?? data['title']?.toString();
    final categoryStr = data['category']?.toString();
    final notesStr = data['notes']?.toString();
    // Any app can send this intent, so "auto" only saves without asking
    // when you've allowed it in Optional features; otherwise the screen
    // opens pre-filled for you to confirm.
    final autoSave = data['auto']?.toString().toLowerCase() == 'true' &&
        AppPrefs.instance.allowAutomationAutoSave;

    double? prefilledAmount;
    if (amountStr != null) {
      prefilledAmount = double.tryParse(amountStr);
    }

    Navigator.of(_context!).push(
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(
          prefilledAmount: prefilledAmount,
          prefilledPayee: payeeStr,
          prefilledCategory: categoryStr,
          prefilledNotes: notesStr,
          autoSave: autoSave,
          fromAutomation: true,
        ),
      ),
    );
  }
}
