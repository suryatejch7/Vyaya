import '../services/app_prefs.dart';

/// A repeating expense or income (weekly, monthly or yearly), auto-created
/// when due.
enum RecurringType { expense, income }

enum RecurringFrequency { weekly, monthly, yearly }

class RecurringEntry {
  final String id;
  final RecurringType type;
  final String title;
  final double amount;

  /// Expense category name (expense only).
  final String category;

  /// Income source (income only).
  final String source;

  final RecurringFrequency frequency;

  /// Monthly / yearly: 1-31. Shorter months use their last day.
  final int dayOfMonth;

  /// Weekly: 1 = Monday … 7 = Sunday.
  final int weekday;

  /// Yearly: 1-12.
  final int month;

  final String? accountId;
  final String? notes;
  final bool active;

  /// Date of the next entry to create (date only).
  final DateTime nextDue;

  RecurringEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    this.category = 'Other',
    this.source = '',
    this.frequency = RecurringFrequency.monthly,
    required this.dayOfMonth,
    this.weekday = 1,
    this.month = 1,
    this.accountId,
    this.notes,
    this.active = true,
    required this.nextDue,
  });

  bool get isIncome => type == RecurringType.income;

  static DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The occurrence of [dayOfMonth] in the given month, clamped to month end.
  static DateTime occurrenceIn(int year, int month, int dayOfMonth) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, dayOfMonth > lastDay ? lastDay : dayOfMonth);
  }

  /// The occurrence after [from] (one week, month or year later).
  DateTime nextAfter(DateTime from) => switch (frequency) {
        RecurringFrequency.weekly =>
          DateTime(from.year, from.month, from.day + 7),
        RecurringFrequency.monthly =>
          occurrenceIn(from.year, from.month + 1, dayOfMonth),
        RecurringFrequency.yearly =>
          occurrenceIn(from.year + 1, month, dayOfMonth),
      };

  /// The occurrence inside the week / month / year that contains [day].
  DateTime occurrenceInPeriodOf(DateTime day) {
    final d = _date(day);
    return switch (frequency) {
      // The chosen weekday within the calendar week (Sunday or Monday start,
      // per Settings) that contains [day].
      RecurringFrequency.weekly => () {
          final start = AppPrefs.instance.weekStartOf(d);
          final offset = (weekday - start.weekday) % 7;
          return DateTime(start.year, start.month, start.day + offset);
        }(),
      RecurringFrequency.monthly => occurrenceIn(d.year, d.month, dayOfMonth),
      RecurringFrequency.yearly => occurrenceIn(d.year, month, dayOfMonth),
    };
  }

  /// First occurrence on or after [from].
  DateTime occurrenceOnOrAfter(DateTime from) {
    final start = _date(from);
    final inPeriod = occurrenceInPeriodOf(start);
    return inPeriod.isBefore(start) ? nextAfter(inPeriod) : inPeriod;
  }

  /// How far back missed entries are created when the app wasn't opened.
  int get catchUpLimit => switch (frequency) {
        RecurringFrequency.weekly => 104,
        RecurringFrequency.monthly => 24,
        RecurringFrequency.yearly => 3,
      };

  /// "this week" / "this month" / "this year".
  String get periodLabel => switch (frequency) {
        RecurringFrequency.weekly => 'this week',
        RecurringFrequency.monthly => 'this month',
        RecurringFrequency.yearly => 'this year',
      };

  static const weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
  }

  /// "Every Monday", "5th of every month", "Every year on 5 Mar".
  String get scheduleLabel => switch (frequency) {
        RecurringFrequency.weekly => 'Every ${weekdayNames[weekday - 1]}',
        RecurringFrequency.monthly => '${ordinal(dayOfMonth)} of every month',
        RecurringFrequency.yearly =>
          'Every year on $dayOfMonth ${monthNames[month - 1]}',
      };

  static RecurringFrequency _freq(Object? v) => switch (v) {
        'weekly' => RecurringFrequency.weekly,
        'yearly' => RecurringFrequency.yearly,
        _ => RecurringFrequency.monthly,
      };

  factory RecurringEntry.fromJson(Map<String, dynamic> j) => RecurringEntry(
        id: j['id'].toString(),
        type: j['type'] == 'income' ? RecurringType.income : RecurringType.expense,
        title: j['title'] ?? '',
        amount: (j['amount'] as num).toDouble(),
        category: j['category'] ?? 'Other',
        source: j['source'] ?? '',
        frequency: _freq(j['frequency']),
        dayOfMonth: (j['day_of_month'] as num?)?.toInt() ?? 1,
        weekday: (j['weekday'] as num?)?.toInt() ?? 1,
        month: (j['month'] as num?)?.toInt() ?? 1,
        accountId: j['account_id'],
        notes: j['notes'],
        active: j['active'] as bool? ?? true,
        nextDue: DateTime.parse(j['next_due']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': isIncome ? 'income' : 'expense',
        'title': title,
        'amount': amount,
        'category': category,
        'source': source,
        'frequency': frequency.name,
        'day_of_month': dayOfMonth,
        'weekday': weekday,
        'month': month,
        'account_id': accountId,
        'notes': notes,
        'active': active,
        'next_due': nextDue.toIso8601String(),
      };

  RecurringEntry copyWith({
    RecurringType? type,
    String? title,
    double? amount,
    String? category,
    String? source,
    RecurringFrequency? frequency,
    int? dayOfMonth,
    int? weekday,
    int? month,
    String? accountId,
    String? notes,
    bool? active,
    DateTime? nextDue,
  }) =>
      RecurringEntry(
        id: id,
        type: type ?? this.type,
        title: title ?? this.title,
        amount: amount ?? this.amount,
        category: category ?? this.category,
        source: source ?? this.source,
        frequency: frequency ?? this.frequency,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        weekday: weekday ?? this.weekday,
        month: month ?? this.month,
        accountId: accountId ?? this.accountId,
        notes: notes ?? this.notes,
        active: active ?? this.active,
        nextDue: nextDue ?? this.nextDue,
      );
}
