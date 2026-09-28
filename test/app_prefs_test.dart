import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expensetracker/services/app_prefs.dart';

Future<AppPrefs> _prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = AppPrefs.instance;
  await prefs.init();
  return prefs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Week start', () {
    test('defaults to Sunday', () async {
      final p = await _prefsWith({});
      expect(p.weekStartsMonday, isFalse);
      // Wed 30 Sep 2026 -> Sun 27 Sep
      expect(p.weekStartOf(DateTime(2026, 9, 30, 18)), DateTime(2026, 9, 27));
      // A Sunday starts its own week; Saturday ends it.
      expect(p.weekStartOf(DateTime(2026, 9, 27)), DateTime(2026, 9, 27));
      expect(p.weekStartOf(DateTime(2026, 10, 3)), DateTime(2026, 9, 27));
      expect(p.weekdayLabels.first, 'Sun');
    });

    test('Monday when chosen', () async {
      final p = await _prefsWith({'ls_opt_week_monday': '1'});
      expect(p.weekStartOf(DateTime(2026, 9, 30)), DateTime(2026, 9, 28));
      // Sunday belongs to the week that began the Monday before.
      expect(p.weekStartOf(DateTime(2026, 9, 27)), DateTime(2026, 9, 21));
      // Across a month boundary.
      expect(p.weekStartOf(DateTime(2026, 10, 1)), DateTime(2026, 9, 28));
    });
  });

  group('Quick actions', () {
    test('Recurring stays in Settings by default', () async {
      final p = await _prefsWith({});
      expect(p.shortcutInSettings, QuickShortcut.recurring);
      expect(p.shortcutsInSheet,
          [QuickShortcut.detected, QuickShortcut.lentBorrowed]);
    });

    test('the chosen one moves to Settings', () async {
      final p = await _prefsWith({'ls_opt_quick_in_settings': 'detected'});
      expect(p.shortcutsInSheet,
          [QuickShortcut.lentBorrowed, QuickShortcut.recurring]);
    });

    test('unknown stored value falls back to Recurring', () async {
      final p = await _prefsWith({'ls_opt_quick_in_settings': 'bogus'});
      expect(p.shortcutInSettings, QuickShortcut.recurring);
    });
  });

  group('Late night counts as yesterday', () {
    test('off: always now', () async {
      final p = await _prefsWith({});
      final t = DateTime(2026, 9, 28, 1, 30);
      expect(p.defaultEntryDate(t), t);
    });

    test('on: before 4 AM goes to 11:59 PM yesterday', () async {
      final p = await _prefsWith({'ls_opt_late_night': '1'});
      expect(p.defaultEntryDate(DateTime(2026, 10, 1, 1, 30)),
          DateTime(2026, 9, 30, 23, 59));
      final after = DateTime(2026, 10, 1, 4, 0);
      expect(p.defaultEntryDate(after), after);
    });
  });

  test('reminder off unless a valid time is stored', () async {
    expect((await _prefsWith({})).reminderMinutes, isNull);
    expect((await _prefsWith({'ls_opt_reminder': '-1'})).reminderMinutes,
        isNull);
    expect((await _prefsWith({'ls_opt_reminder': '1260'})).reminderMinutes,
        1260);
  });
}
