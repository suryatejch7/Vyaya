/// A monthly repeating expense or income, auto-created when due.
enum RecurringType { expense, income }

class RecurringEntry {
  final String id;
  final RecurringType type;
  final String title;
  final double amount;

  /// Expense category name (expense only).
  final String category;

  /// Income source (income only).
  final String source;

  /// 1-31. Months shorter than this use their last day.
  final int dayOfMonth;
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
    required this.dayOfMonth,
    this.accountId,
    this.notes,
    this.active = true,
    required this.nextDue,
  });

  bool get isIncome => type == RecurringType.income;

  /// The occurrence of [dayOfMonth] in the given month, clamped to month end.
  static DateTime occurrenceIn(int year, int month, int dayOfMonth) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, dayOfMonth > lastDay ? lastDay : dayOfMonth);
  }

  /// The occurrence one month after [from].
  DateTime nextAfter(DateTime from) =>
      occurrenceIn(from.year, from.month + 1, dayOfMonth);

  factory RecurringEntry.fromJson(Map<String, dynamic> j) => RecurringEntry(
        id: j['id'].toString(),
        type: j['type'] == 'income' ? RecurringType.income : RecurringType.expense,
        title: j['title'] ?? '',
        amount: (j['amount'] as num).toDouble(),
        category: j['category'] ?? 'Other',
        source: j['source'] ?? '',
        dayOfMonth: (j['day_of_month'] as num?)?.toInt() ?? 1,
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
        'day_of_month': dayOfMonth,
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
    int? dayOfMonth,
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
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        accountId: accountId ?? this.accountId,
        notes: notes ?? this.notes,
        active: active ?? this.active,
        nextDue: nextDue ?? this.nextDue,
      );
}
