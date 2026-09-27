/// Money lent to or borrowed from a person. Tracked separately from
/// expenses/income so it doesn't affect spending totals.
class DebtEntry {
  final String id;
  final String person;
  final double amount;

  /// true = you lent (they owe you); false = you borrowed (you owe them).
  final bool isLent;
  final DateTime date;
  final String? note;
  final bool settled;
  final DateTime? settledAt;

  DebtEntry({
    required this.id,
    required this.person,
    required this.amount,
    required this.isLent,
    required this.date,
    this.note,
    this.settled = false,
    this.settledAt,
  });

  /// + if they owe you, - if you owe them.
  double get signedAmount => isLent ? amount : -amount;

  factory DebtEntry.fromJson(Map<String, dynamic> j) => DebtEntry(
        id: j['id'].toString(),
        person: j['person'] ?? '',
        amount: (j['amount'] as num).toDouble(),
        isLent: j['is_lent'] as bool? ?? true,
        date: DateTime.parse(j['date']),
        note: j['note'],
        settled: j['settled'] as bool? ?? false,
        settledAt:
            j['settled_at'] != null ? DateTime.parse(j['settled_at']) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'person': person,
        'amount': amount,
        'is_lent': isLent,
        'date': date.toIso8601String(),
        'note': note,
        'settled': settled,
        'settled_at': settledAt?.toIso8601String(),
      };

  DebtEntry copyWith({
    String? person,
    double? amount,
    bool? isLent,
    DateTime? date,
    String? note,
    bool? settled,
    DateTime? settledAt,
    bool clearSettledAt = false,
  }) =>
      DebtEntry(
        id: id,
        person: person ?? this.person,
        amount: amount ?? this.amount,
        isLent: isLent ?? this.isLent,
        date: date ?? this.date,
        note: note ?? this.note,
        settled: settled ?? this.settled,
        settledAt: clearSettledAt ? null : (settledAt ?? this.settledAt),
      );
}
