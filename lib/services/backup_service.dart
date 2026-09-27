import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/expense_provider.dart';
import '../providers/user_provider.dart';
import 'cache_service.dart';
import 'supabase_service.dart';

/// Full JSON backup & restore of all app data.
///
/// - **Backup**: serialises every `ls_*` key from SharedPreferences into a
///   single JSON file and opens the platform share sheet so the user can save
///   it anywhere (Drive, Files, email …).
/// - **Restore**: reads a previously exported JSON file, writes the values back
///   into SharedPreferences, and reloads the providers.
/// - **Auto-file backup**: after every write the service can persist a shadow
///   copy in the app's documents directory. This file is included in Android
///   Auto Backup so it survives reinstalls even without a manual export.
class BackupService {
  // -------------------- constants --------------------
  static const String _autoBackupFileName = 'expense_tracker_auto_backup.json';
  static const String _lsPrefix = 'ls_';

  // -------------------- AUTO FILE BACKUP --------------------

  /// Writes a snapshot of all `ls_*` keys to the internal documents directory.
  /// Called automatically after every data-mutating operation.
  static Future<void> autoSave() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backup = <String, dynamic>{};

      for (final key in prefs.getKeys()) {
        if (key.startsWith(_lsPrefix)) {
          backup[key] = prefs.get(key);
        }
      }

      backup['_backup_timestamp'] = DateTime.now().toIso8601String();
      backup['_backup_version'] = 1;

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_autoBackupFileName');
      await file.writeAsString(jsonEncode(backup));
    } catch (_) {
      // Fail silently – auto-backup is a best-effort safety net.
    }
  }

  /// On startup, if SharedPreferences has no `ls_` data but an auto-backup
  /// file exists, restore from it. Returns `true` if a restore happened.
  static Future<bool> restoreFromAutoBackupIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasData = prefs.getKeys().any((k) => k.startsWith(_lsPrefix));
      if (hasData) return false;

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_autoBackupFileName');
      if (!await file.exists()) return false;

      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      await _writeMapToPrefs(prefs, json);
      return true;
    } catch (_) {
      return false;
    }
  }

  // -------------------- MANUAL BACKUP --------------------

  /// Creates a timestamped JSON backup and opens the share sheet.
  static Future<void> createAndShareBackup(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backup = <String, dynamic>{};

      for (final key in prefs.getKeys()) {
        if (key.startsWith(_lsPrefix)) {
          backup[key] = prefs.get(key);
        }
      }

      backup['_backup_timestamp'] = DateTime.now().toIso8601String();
      backup['_backup_version'] = 1;

      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${dir.path}/expense_tracker_backup_$ts.json');
      await file.writeAsString(jsonEncode(backup));

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Vyaya Backup',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // -------------------- MANUAL RESTORE --------------------

  /// Restores from a JSON backup file at [filePath].
  /// Replaces all `ls_*` data, re-selects the restored user, then reloads
  /// providers in place (the app has no login screen to bounce through).
  static Future<bool> restoreFromFile(
    BuildContext context,
    String filePath,
  ) async {
    // Grab these before any await / navigation so we never touch a
    // deactivated context afterwards.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final expenseProvider =
        Provider.of<ExpenseProvider>(context, listen: false);

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _showError(context, 'Backup file not found.');
        return false;
      }

      final content = await file.readAsString();
      final json = jsonDecode(content);
      if (json is! Map<String, dynamic>) {
        _showError(context, 'Invalid backup file format.');
        return false;
      }

      // Validate it looks like our backup
      final hasLsKeys = json.keys.any((k) => k.startsWith(_lsPrefix));
      if (!hasLsKeys) {
        _showError(context, 'This file does not contain valid app data.');
        return false;
      }

      // Work out which user the backup belongs to BEFORE touching storage.
      final restoredUserId = _pickUserId(json);
      if (restoredUserId == null) {
        _showError(context, 'Backup has no user data to restore.');
        return false;
      }

      // Replace app data only (ls_* keys). Keeps unrelated prefs such as
      // notification settings intact.
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(_lsPrefix)) await prefs.remove(key);
      }
      await _writeMapToPrefs(prefs, json);

      // Stale expense/settings cache would otherwise show pre-restore data.
      await CacheService.clearAllCache();
      await ExpenseSupabaseService.initialize();

      // Select the restored user (also writes the `userId` pref, which the
      // backup doesn't contain) and reload everything in place.
      expenseProvider.clearUserData();
      final ok = await userProvider.loginWithUserId(restoredUserId);
      if (!ok) {
        messenger.showSnackBar(SnackBar(
          content: Text('Restore failed: ${userProvider.errorMessage ?? 'user not found'}'),
          backgroundColor: Colors.red,
        ));
        return false;
      }
      await userProvider.initializeExpenseProvider(expenseProvider);

      // Keep the shadow auto-backup in sync with what was just restored.
      await autoSave();

      navigator.popUntil((route) => route.isFirst);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Backup restored successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      return true;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Restore failed: $e'), backgroundColor: Colors.red),
      );
      return false;
    }
  }

  /// Picks the user id to activate from a backup map: the first user in
  /// `ls_users` that has a settings entry, else the first user at all.
  static int? _pickUserId(Map<String, dynamic> data) {
    final rawUsers = data['ls_users'];
    if (rawUsers is! String) return null;
    final users = (jsonDecode(rawUsers) as List)
        .map((u) => (u as Map)['id'])
        .whereType<int>()
        .toList();
    if (users.isEmpty) return null;
    return users.firstWhere(
      (id) => data.containsKey('ls_settings_$id'),
      orElse: () => users.first,
    );
  }

  // -------------------- helpers --------------------

  static Future<void> _writeMapToPrefs(
    SharedPreferences prefs,
    Map<String, dynamic> data,
  ) async {
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      // Skip metadata keys
      if (key.startsWith('_')) continue;

      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.cast<String>());
      }
    }
  }

  static void _showError(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }
}
