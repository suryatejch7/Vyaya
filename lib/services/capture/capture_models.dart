/// A payment picked up from a bank SMS or payment-app notification.
class DetectedTransaction {
  final String id;

  /// Native queue ids merged into this item (same payment from 2+ sources).
  final List<int> captureIds;

  /// 'sms' | 'notification' (of the first capture)
  final String sourceKind;

  /// Human label: "PhonePe", "HDFC Bank", "Bank SMS"…
  final String appLabel;
  final String rawText;
  final double amount;
  final bool isDebit;
  final String? merchant;
  final String? last4;
  final String? reference;
  final DateTime occurredAt;
  final DateTime capturedAt;
  final double confidence;
  final List<String> flags;
  final String category;
  final bool fromImport;

  /// 'pending' | 'added' | 'dismissed' | 'duplicate'
  final String status;

  /// Expense/income id once added, or the manual entry it duplicates.
  final String? entryId;

  /// Who sent it: the SMS header code ("HDFCBK") or the app's package name.
  /// Used by "Always ignore" rules. Null for items captured before it existed.
  final String? sender;

  const DetectedTransaction({
    required this.id,
    required this.captureIds,
    required this.sourceKind,
    required this.appLabel,
    required this.rawText,
    required this.amount,
    required this.isDebit,
    required this.merchant,
    required this.last4,
    required this.reference,
    required this.occurredAt,
    required this.capturedAt,
    required this.confidence,
    required this.flags,
    required this.category,
    required this.fromImport,
    required this.status,
    this.entryId,
    this.sender,
  });

  String get title =>
      merchant ?? (isDebit ? 'UPI payment' : 'Money received');

  bool get isPending => status == 'pending';

  factory DetectedTransaction.fromJson(Map<String, dynamic> j) =>
      DetectedTransaction(
        id: j['id'].toString(),
        captureIds: ((j['capture_ids'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        sourceKind: j['source_kind'] ?? 'sms',
        appLabel: j['app_label'] ?? 'Bank SMS',
        rawText: j['raw_text'] ?? '',
        amount: (j['amount'] as num).toDouble(),
        isDebit: j['is_debit'] as bool? ?? true,
        merchant: j['merchant'],
        last4: j['last4'],
        reference: j['reference'],
        occurredAt: DateTime.parse(j['occurred_at']),
        capturedAt: DateTime.parse(j['captured_at']),
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.5,
        flags: ((j['flags'] as List?) ?? const []).cast<String>(),
        category: j['category'] ?? 'Other',
        fromImport: j['from_import'] as bool? ?? false,
        status: j['status'] ?? 'pending',
        entryId: j['entry_id'],
        sender: j['sender'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'capture_ids': captureIds,
        'source_kind': sourceKind,
        'app_label': appLabel,
        'raw_text': rawText,
        'amount': amount,
        'is_debit': isDebit,
        'merchant': merchant,
        'last4': last4,
        'reference': reference,
        'occurred_at': occurredAt.toIso8601String(),
        'captured_at': capturedAt.toIso8601String(),
        'confidence': confidence,
        'flags': flags,
        'category': category,
        'from_import': fromImport,
        'status': status,
        'entry_id': entryId,
        'sender': sender,
      };

  DetectedTransaction copyWith({
    List<int>? captureIds,
    String? rawText,
    String? merchant,
    String? last4,
    String? reference,
    List<String>? flags,
    String? category,
    String? status,
    String? entryId,
  }) =>
      DetectedTransaction(
        id: id,
        captureIds: captureIds ?? this.captureIds,
        sourceKind: sourceKind,
        appLabel: appLabel,
        rawText: rawText ?? this.rawText,
        amount: amount,
        isDebit: isDebit,
        merchant: merchant ?? this.merchant,
        last4: last4 ?? this.last4,
        reference: reference ?? this.reference,
        occurredAt: occurredAt,
        capturedAt: capturedAt,
        confidence: confidence,
        flags: flags ?? this.flags,
        category: category ?? this.category,
        fromImport: fromImport,
        status: status ?? this.status,
        entryId: entryId ?? this.entryId,
        sender: sender,
      );
}

/// "Always ignore" rule for auto-detection: a payee name or a sender.
class MuteRule {
  /// 'payee' | 'sender'
  final String type;

  /// Normalised payee name, or the sender code / app package.
  final String value;

  /// What to show the user: "Swiggy", "HDFC Bank (HDFCBK)", "Paytm".
  final String label;

  const MuteRule({required this.type, required this.value, required this.label});

  bool get isPayee => type == 'payee';

  factory MuteRule.fromJson(Map<String, dynamic> j) => MuteRule(
        type: j['type'] ?? 'payee',
        value: j['value'] ?? '',
        label: j['label'] ?? j['value'] ?? '',
      );

  Map<String, dynamic> toJson() => {'type': type, 'value': value, 'label': label};

  @override
  bool operator ==(Object other) =>
      other is MuteRule && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);
}
