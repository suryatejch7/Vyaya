import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/expense_provider.dart';
import '../providers/user_provider.dart';
import '../providers/capture_provider.dart';
import '../models/expense_models.dart';
import '../models/user_settings.dart';
import '../models/recurring_entry.dart';
import '../models/debt_entry.dart';
import 'capture/capture_models.dart';
import 'local_store.dart';
import 'app_prefs.dart';
import 'notification_service.dart';

/// Full JSON backup & restore of all app data.
///
/// - **Backup**: serialises every `ls_*` key from SharedPreferences into a
///   single JSON file and opens the platform share sheet so the user can save
///   it anywhere (Drive, Files, email …).
/// - **Restore**: reads a previously exported JSON file, writes the values back
///   into SharedPreferences, and reloads the providers.
/// - **Auto-file backup**: after every write the service can persist a shadow
///   copy in the app's documents directory, used if SharedPreferences is
///   wiped while the app's files remain. It is NOT in Android's cloud backup
///   (allowBackup is off: the app is offline-only), so uninstalling or
///   clearing storage removes it too; only a manual export survives that.
class BackupService {
  // -------------------- constants --------------------
  static const String _autoBackupFileName = 'expense_tracker_auto_backup.json';
  static const String _lsPrefix = 'ls_';

  /// The app-lock PIN stays on this phone: it isn't put in shared backups
  /// and a restore never replaces it.
  static const String _pinKey = 'ls_opt_pin_hash';
  static const String _intentAutoSaveKey = 'ls_opt_intent_autosave';

  // -------------------- AUTO FILE BACKUP --------------------

  static Timer? _autoSaveTimer;
  static bool _autoSaving = false;
  static bool _autoSaveAgain = false;

  /// Asks for a fresh safety copy. Changes are grouped: the copy is written
  /// 3 s after the last change, one at a time, off the UI thread.
  static void autoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 3), writeAutoBackup);
  }

  /// Writes a pending safety copy now (the app is going to the background).
  static Future<void> flushPending() async {
    if (_autoSaveTimer != null) await writeAutoBackup();
  }

  /// Drops a pending safety copy (restore / reset replace the data).
  static void cancelPending() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  /// Writes a snapshot of all `ls_*` keys to the internal documents
  /// directory now (used by [autoSave], and after a restore).
  static Future<void> writeAutoBackup() async {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    if (_autoSaving) {
      _autoSaveAgain = true; // one more pass when the current one ends
      return;
    }
    _autoSaving = true;
    try {
      await LocalStore.flush();
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
      final path = '${dir.path}/$_autoBackupFileName';
      // Encoding and writing happen on a background isolate. Written to a
      // temp file and renamed, so an interrupted write never leaves a
      // half-written (unreadable) safety copy.
      await Isolate.run(() {
        // Named *.tmp.json so "Reset All Data" also removes a leftover.
        final tmp = File(path.replaceFirst(RegExp(r'\.json$'), '.tmp.json'));
        tmp.writeAsStringSync(jsonEncode(backup), flush: true);
        tmp.renameSync(path);
      });
    } catch (_) {
      // Fail silently – auto-backup is a best-effort safety net.
    } finally {
      _autoSaving = false;
      if (_autoSaveAgain) {
        _autoSaveAgain = false;
        autoSave();
      }
    }
  }

  /// Deletes the backup and CSV copies Vyaya saved in its own storage
  /// (auto-backup, shared backups, exports). Used by Reset All Data.
  static Future<void> deleteSavedFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final f in dir.listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (name.startsWith('expense_tracker_') &&
            (name.endsWith('.json') || name.endsWith('.csv'))) {
          await f.delete();
        }
      }
    } catch (_) {
      // Best effort: the data itself is already cleared.
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
      await LocalStore.flush(); // include changes from the last moment
      final prefs = await SharedPreferences.getInstance();
      final backup = <String, dynamic>{};

      for (final key in prefs.getKeys()) {
        if (key.startsWith(_lsPrefix) && key != _pinKey) {
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
    final captureProvider =
        Provider.of<CaptureProvider>(context, listen: false);
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

      // Check the data can actually be read BEFORE touching storage, so a
      // damaged backup can't wipe what's on the phone.
      final problem = _findDamage(json);
      if (problem != null) {
        _showError(context,
            'This backup is damaged ($problem). Nothing was changed.');
        return false;
      }

      // Replace app data only (ls_* keys); other prefs stay as they are.
      // The current data is kept in memory
      // and put back if anything below fails.
      cancelPending(); // no safety copy of a half-restored state
      await LocalStore.flush(); // so the rollback copy is complete
      final prefs = await SharedPreferences.getInstance();
      final previous = <String, dynamic>{
        for (final k in prefs.getKeys())
          if (k.startsWith(_lsPrefix)) k: prefs.get(k),
      };
      final previousUserId = userProvider.currentUser?.id;
      try {
        // Unwritten changes must not land on top of the restored data.
        LocalStore.discardPending();
        for (final key in prefs.getKeys().toList()) {
          if (key.startsWith(_lsPrefix) &&
              key != _pinKey &&
              key != _intentAutoSaveKey) {
            await prefs.remove(key);
          }
        }
        // Only app data (ls_*) is written; this phone's PIN and the
        // "automation apps can save directly" switch are never taken from
        // a file (a backup from someone else could turn that on).
        await _writeMapToPrefs(prefs, {
          for (final e in json.entries)
            if (e.key.startsWith(_lsPrefix) &&
                e.key != _pinKey &&
                e.key != _intentAutoSaveKey)
              e.key: e.value,
        });

        await LocalStore.initialize();

        // Select the restored user (also writes the `userId` pref, which the
        // backup doesn't contain) and reload everything in place.
        expenseProvider.clearUserData();
        final ok = await userProvider.loginWithUserId(restoredUserId);
        if (!ok) throw userProvider.errorMessage ?? 'user not found';
        await userProvider.initializeExpenseProvider(expenseProvider);
        await captureProvider.reload(); // detected payments from the backup
      } catch (e) {
        // Put the phone's data back exactly as it was, and drop anything
        // from the backup that was already loaded into memory.
        LocalStore.discardPending();
        expenseProvider.clearUserData();
        for (final key in prefs.getKeys().toList()) {
          if (key.startsWith(_lsPrefix)) await prefs.remove(key);
        }
        await _writeMapToPrefs(prefs, previous);
        await LocalStore.initialize();
        if (previousUserId != null) {
          await userProvider.loginWithUserId(previousUserId);
          await userProvider.initializeExpenseProvider(expenseProvider);
          await captureProvider.reload();
        }
        messenger.showSnackBar(SnackBar(
          content: Text('Restore failed: $e. Your data was not changed.'),
          backgroundColor: Colors.red,
        ));
        return false;
      }
      // Optional features came back too: re-schedule the daily reminder.
      await AppPrefs.instance
          .reloadAfterDataChange(NotificationService.syncDailyReminder);
      await NotificationService.syncDetectedNotifier();

      // Keep the shadow auto-backup in sync with what was just restored.
      await writeAutoBackup();

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

  /// Tries to read every expense, income and settings entry in a backup.
  /// Returns what's wrong, or null when it all reads fine.
  static String? _findDamage(Map<String, dynamic> data) {
    for (final e in data.entries) {
      final k = e.key;
      try {
        if (k.startsWith('ls_expenses_')) {
          for (final m in jsonDecode(e.value as String) as List) {
            Expense.fromJson(Map<String, dynamic>.from(m as Map));
          }
        } else if (k.startsWith('ls_incomes_')) {
          for (final m in jsonDecode(e.value as String) as List) {
            Income.fromJson(Map<String, dynamic>.from(m as Map));
          }
        } else if (k.startsWith('ls_settings_')) {
          UserSettings.fromJson(
              Map<String, dynamic>.from(jsonDecode(e.value as String) as Map));
        } else if (k == 'ls_users') {
          jsonDecode(e.value as String) as List;
        } else if (k.startsWith('ls_recurring_')) {
          for (final m in jsonDecode(e.value as String) as List) {
            RecurringEntry.fromJson(Map<String, dynamic>.from(m as Map));
          }
        } else if (k.startsWith('ls_debts_')) {
          for (final m in jsonDecode(e.value as String) as List) {
            DebtEntry.fromJson(Map<String, dynamic>.from(m as Map));
          }
        } else if (RegExp(r'^ls_detected_\d+$').hasMatch(k)) {
          for (final m in jsonDecode(e.value as String) as List) {
            DetectedTransaction.fromJson(Map<String, dynamic>.from(m as Map));
          }
        }
      } catch (_) {
        return k.replaceFirst(_lsPrefix, '');
      }
    }
    return null;
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
