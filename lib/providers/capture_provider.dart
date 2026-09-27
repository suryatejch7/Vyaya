import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vyaya_capture/vyaya_capture.dart';

import '../models/expense_models.dart';
import '../services/capture/capture_models.dart';
import '../services/capture/merchant_categorizer.dart';
import '../services/capture/transaction_parser.dart';
import '../services/supabase_service.dart';
import 'expense_provider.dart';

/// Auto-detects payments from bank SMS and payment-app notifications.
///
/// Flow: native queue -> [TransactionParser] -> de-duplicate (same payment
/// from two sources, or already logged by hand) -> categorise -> either add
/// right away ("auto" mode, confident matches only) or keep for review.
class CaptureProvider extends ChangeNotifier {
  static const _itemsKey = 'detected';
  static const _rulesKey = 'merchant_rules';
  static const _modeKey = 'capture_mode';
  static const _maxItems = 600;

  ExpenseProvider? _expenses;
  StreamSubscription<void>? _eventSub;
  bool _syncing = false;
  bool _resyncRequested = false;

  final List<DetectedTransaction> _items = [];
  final Map<String, String> _rules = {};
  String _mode = 'ask';
  bool _notificationAccess = false;
  bool _smsPermission = false;

  // ---------------------------------------------------------------- getters

  bool get autoMode => _mode == 'auto';
  bool get notificationAccess => _notificationAccess;
  bool get smsPermission => _smsPermission;
  bool get isEnabled => _notificationAccess || _smsPermission;

  List<DetectedTransaction> _byStatus(String s) =>
      _items.where((i) => i.status == s).toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

  List<DetectedTransaction> get pending => _byStatus('pending');
  List<DetectedTransaction> get added => _byStatus('added');
  List<DetectedTransaction> get duplicates => _byStatus('duplicate');
  List<DetectedTransaction> get dismissed => _byStatus('dismissed');
  int get pendingCount => _items.where((i) => i.isPending).length;

  int get _userId => _expenses?.userId ?? 0;

  // -------------------------------------------------------------- lifecycle

  /// Call once the ExpenseProvider has loaded the user's data.
  Future<void> attach(ExpenseProvider expenses) async {
    _expenses = expenses;
    await _load();
    _eventSub ??= VyayaCapture.events.listen((_) => sync());
    await refreshStatus();
    if (_notificationAccess) await VyayaCapture.requestRebind();
    await sync();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  /// Re-reads stored items after a backup restore or data reset.
  Future<void> reload() async {
    await _load();
    await refreshStatus();
  }

  Future<void> refreshStatus() async {
    _notificationAccess = await VyayaCapture.isNotificationAccessGranted();
    _smsPermission = await VyayaCapture.hasSmsPermission();
    notifyListeners();
  }

  Future<void> _load() async {
    if (_userId == 0) return;
    final raw = await ExpenseSupabaseService.getJsonList(_itemsKey, userId: _userId);
    _items
      ..clear()
      ..addAll(raw.map(DetectedTransaction.fromJson));
    _rules.clear();
    final rules = ExpenseSupabaseService.getMeta(_rulesKey, userId: _userId);
    if (rules != null) {
      try {
        _rules.addAll(Map<String, String>.from(jsonDecode(rules) as Map));
      } catch (_) {}
    }
    _mode = ExpenseSupabaseService.getMeta(_modeKey, userId: _userId) ?? 'ask';
    notifyListeners();
  }

  Future<void> _save() async {
    // Keep storage bounded: drop the oldest non-pending items first.
    if (_items.length > _maxItems) {
      _items.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      final keep = <DetectedTransaction>[];
      var others = 0;
      for (final i in _items) {
        if (i.isPending || others < _maxItems) keep.add(i);
        if (!i.isPending) others++;
      }
      _items
        ..clear()
        ..addAll(keep);
    }
    await ExpenseSupabaseService.saveJsonList(
        _itemsKey, _items.map((i) => i.toJson()).toList(),
        userId: _userId);
  }

  Future<void> _saveRules() => ExpenseSupabaseService.setMeta(
      _rulesKey, jsonEncode(_rules),
      userId: _userId);

  // ------------------------------------------------------------ permissions

  Future<void> openNotificationAccess() =>
      VyayaCapture.openNotificationAccessSettings();

  Future<void> openAppDetails() => VyayaCapture.openAppDetails();

  /// Returns true if granted.
  Future<bool> requestSmsPermission() async {
    final status = await Permission.sms.request();
    await refreshStatus();
    return status.isGranted;
  }

  Future<void> requestBatteryExemption() async {
    await Permission.ignoreBatteryOptimizations.request();
  }

  Future<void> setAutoMode(bool auto) async {
    _mode = auto ? 'auto' : 'ask';
    await ExpenseSupabaseService.setMeta(_modeKey, _mode, userId: _userId);
    notifyListeners();
  }

  /// Imports bank SMS from the last [days] days into the review list.
  /// Imported items are never auto-added. Returns how many new items appeared.
  Future<int> importRecentSms({int days = 30}) async {
    if (!_smsPermission && !await requestSmsPermission()) return 0;
    final before = _items.length;
    await VyayaCapture.backfillSms(
        DateTime.now().subtract(Duration(days: days)));
    await sync();
    return _items.length - before;
  }

  // ------------------------------------------------------------------ sync

  /// Drains the native queue. Safe to call often (app resume, events).
  Future<void> sync() async {
    if (_expenses == null || _userId == 0) return;
    if (_syncing) {
      _resyncRequested = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _resyncRequested = false;
        for (var round = 0; round < 20; round++) {
          final batch = await VyayaCapture.fetchPending(limit: 200);
          if (batch.isEmpty) break;
          for (final record in batch) {
            await _ingest(record);
          }
          await _save(); // persist before acknowledging (crash-safe)
          await VyayaCapture.markConsumed(batch.map((r) => r.id).toList());
          notifyListeners();
        }
      } while (_resyncRequested);
      await VyayaCapture.clearNotifier();
    } catch (e) {
      debugPrint('Capture sync failed: $e');
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _ingest(CaptureRecord r) async {
    if (_items.any((i) => i.captureIds.contains(r.id))) return; // replay

    final kind = r.source == 'notification' ? 'notification' : 'sms';
    final result = TransactionParser.parse(r.body,
        source: kind, sender: r.sender, postedAt: r.postedAt);
    final t = result.transaction;
    if (t == null) return;

    // 1) The same payment reported by another source (or re-read)?
    final same = _findSamePayment(t, kind, r.postedAt);
    if (same != null) {
      await _merge(same, t, r);
      return;
    }

    // 2) Already logged by hand?
    final manualId = _findManualEntry(t, r.postedAt, lenient: r.backfill);

    final category = MerchantCategorizer.suggest(
      merchant: t.merchant,
      rawText: r.body,
      categoryNames: _expenses!.categories.map((c) => c.name).toList(),
      learned: _rules,
    );

    final item = DetectedTransaction(
      id: '${r.postedAt.millisecondsSinceEpoch}-${r.id}',
      captureIds: [r.id],
      sourceKind: kind,
      appLabel: _label(kind, r.sender),
      rawText: r.body,
      amount: t.amount,
      isDebit: t.isDebit,
      merchant: t.merchant,
      last4: t.last4,
      reference: t.reference,
      occurredAt: t.occurredAt,
      capturedAt: r.postedAt,
      confidence: t.confidence,
      flags: t.flags.toList(),
      category: category,
      fromImport: r.backfill,
      status: manualId != null ? 'duplicate' : 'pending',
      entryId: manualId,
    );
    _items.add(item);

    if (item.isPending && _shouldAutoAdd(item)) {
      await _addToLedger(item);
    }
  }

  bool _shouldAutoAdd(DetectedTransaction i) =>
      autoMode &&
      !i.fromImport &&
      i.confidence >= 0.8 &&
      !i.flags.any((f) => const {'transfer', 'reversal', 'link'}.contains(f));

  // ---------------------------------------------------------- de-duplication

  static bool _refsMatch(String? a, String? b) {
    if (a == null || b == null) return false;
    final l = a.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final r = b.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (l.length < 6 || r.length < 6) return false;
    if (l == r) return true;
    final longer = l.length >= r.length ? l : r;
    final shorter = l.length >= r.length ? r : l;
    // Banks often quote only part of a 12-digit UTR.
    return longer.startsWith(shorter) || longer.endsWith(shorter);
  }

  static bool _merchantsMatch(String? a, String? b) {
    if (a == null || b == null) return false;
    final x = MerchantCategorizer.key(a);
    final y = MerchantCategorizer.key(b);
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    if (x.length < 4 || y.length < 4) return false;
    return x.contains(y) || y.contains(x);
  }

  /// Same amount + direction, and then:
  /// - both have references -> they must match;
  /// - different sources (app notification vs bank SMS) -> within 5 min, or
  ///   within 3 h with the same payee;
  /// - same source -> only within 2 min (re-posted notification / re-read SMS).
  DetectedTransaction? _findSamePayment(
      ParsedTransaction t, String kind, DateTime capturedAt) {
    final horizon = capturedAt.subtract(const Duration(days: 14));
    for (final i in _items.reversed) {
      if (i.capturedAt.isBefore(horizon)) continue;
      if ((i.amount - t.amount).abs() > 0.009 || i.isDebit != t.isDebit) {
        continue;
      }
      if (i.reference != null && t.reference != null) {
        if (_refsMatch(i.reference, t.reference)) return i;
        continue;
      }
      final gap = i.capturedAt.difference(capturedAt).abs();
      if (i.sourceKind != kind) {
        if (gap <= const Duration(minutes: 5)) return i;
        if (gap <= const Duration(hours: 3) &&
            _merchantsMatch(i.merchant, t.merchant)) {
          return i;
        }
      } else if (gap <= const Duration(minutes: 2) &&
          (i.merchant == null ||
              t.merchant == null ||
              _merchantsMatch(i.merchant, t.merchant))) {
        return i;
      }
    }
    return null;
  }

  /// An expense/income the user logged themselves for this payment.
  /// Live: logged within 30 min, or same day with the same payee.
  /// Import (lenient): same amount on the same day.
  String? _findManualEntry(ParsedTransaction t, DateTime capturedAt,
      {required bool lenient}) {
    final ep = _expenses!;
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    bool closeInTime(DateTime created) =>
        created.difference(capturedAt).abs() <= const Duration(minutes: 30);

    if (t.isDebit) {
      for (final e in ep.expenses) {
        if ((e.amount - t.amount).abs() > 0.009) continue;
        final tid = e.transactionId ?? '';
        if (tid.startsWith('cap-') || tid.startsWith('auto-saved-')) continue;
        if (closeInTime(e.createdAt) ||
            (sameDay(e.date, t.occurredAt) &&
                (lenient || _merchantsMatch(e.description, t.merchant)))) {
          return e.id;
        }
      }
    } else {
      for (final inc in ep.incomes) {
        if ((inc.amount - t.amount).abs() > 0.009) continue;
        if ((inc.notes ?? '').startsWith('Auto-detected')) continue;
        if (closeInTime(inc.createdAt) ||
            (sameDay(inc.date, t.occurredAt) &&
                (lenient || _merchantsMatch(inc.title, t.merchant)))) {
          return inc.id;
        }
      }
    }
    return null;
  }

  /// Folds a second report of the same payment into the existing item,
  /// filling in anything it was missing (payee, account, reference).
  Future<void> _merge(
      DetectedTransaction existing, ParsedTransaction t, CaptureRecord r) async {
    final idx = _items.indexWhere((i) => i.id == existing.id);
    if (idx == -1) return;
    final gainedMerchant = existing.merchant == null && t.merchant != null;
    var updated = existing.copyWith(
      captureIds: [...existing.captureIds, r.id],
      rawText: '${existing.rawText}\n\n${r.body}',
      merchant: existing.merchant ?? t.merchant,
      last4: existing.last4 ?? t.last4,
      reference: existing.reference ?? t.reference,
    );
    if (gainedMerchant && existing.isPending) {
      updated = updated.copyWith(
        category: MerchantCategorizer.suggest(
          merchant: t.merchant,
          rawText: r.body,
          categoryNames: _expenses!.categories.map((c) => c.name).toList(),
          learned: _rules,
        ),
      );
    }
    _items[idx] = updated;

    // Already logged as a nameless "UPI payment"? Give it the payee's name.
    if (gainedMerchant && existing.status == 'added' && existing.isDebit) {
      final ep = _expenses!;
      for (final e in ep.expenses) {
        if (e.transactionId == 'cap-${existing.id}' &&
            e.description == existing.title) {
          await ep.updateExpense(e.copyWith(
            description: t.merchant,
            updatedAt: DateTime.now(),
          ));
          break;
        }
      }
    }
  }

  // --------------------------------------------------------------- actions

  Future<void> _addToLedger(DetectedTransaction item, {String? category}) async {
    final ep = _expenses!;
    final now = DateTime.now();
    final names = ep.categories.map((c) => c.name).toSet();
    var cat = category ?? item.category;
    if (!names.contains(cat)) cat = names.contains('Other') ? 'Other' : cat;

    final accountId = await _resolveAccount(item);
    String? entryId;
    if (item.isDebit) {
      final tag = 'cap-${item.id}';
      await ep.addExpense(Expense(
        amount: item.amount,
        description: item.title,
        category: cat,
        date: item.occurredAt,
        paymentApp: item.appLabel,
        transactionId: tag,
        notes: 'Auto-detected from ${item.appLabel}',
        accountId: accountId,
        createdAt: now,
        updatedAt: now,
      ));
      for (final e in ep.expenses) {
        if (e.transactionId == tag) {
          entryId = e.id;
          break;
        }
      }
    } else {
      await ep.addIncome(Income(
        amount: item.amount,
        title: item.title,
        source: item.appLabel,
        date: item.occurredAt,
        notes: 'Auto-detected from ${item.appLabel}',
        accountId: accountId,
        createdAt: now,
        updatedAt: now,
      ));
      for (final inc in ep.incomes) {
        if (inc.createdAt == now && (inc.amount - item.amount).abs() < 0.009) {
          entryId = inc.id;
          break;
        }
      }
    }
    _replace(item.copyWith(status: 'added', category: cat, entryId: entryId));
  }

  void _replace(DetectedTransaction updated) {
    final idx = _items.indexWhere((i) => i.id == updated.id);
    if (idx != -1) _items[idx] = updated;
  }

  DetectedTransaction? byId(String id) {
    for (final i in _items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Adds a reviewed item. Changing the suggested category teaches the app
  /// that payee's category for next time.
  Future<void> accept(String id, {String? category}) async {
    final item = byId(id);
    if (item == null || item.status == 'added') return;
    if (category != null && category != item.category) {
      _learn(item.merchant, category);
    }
    await _addToLedger(item, category: category);
    await _save();
    notifyListeners();
  }

  Future<void> acceptAll() async {
    for (final item in pending) {
      await _addToLedger(item);
    }
    await _save();
    notifyListeners();
  }

  Future<void> dismiss(String id) async {
    final item = byId(id);
    if (item == null) return;
    _replace(item.copyWith(status: 'dismissed'));
    await _save();
    notifyListeners();
  }

  /// Dismisses everything waiting for review. Returns their ids (for undo).
  Future<List<String>> dismissAll() async {
    final ids = pending.map((i) => i.id).toList();
    for (final id in ids) {
      final item = byId(id);
      if (item != null) _replace(item.copyWith(status: 'dismissed'));
    }
    await _save();
    notifyListeners();
    return ids;
  }

  /// Undo for [dismissAll].
  Future<void> restoreMany(List<String> ids) async {
    for (final id in ids) {
      final item = byId(id);
      if (item != null && item.status == 'dismissed') {
        _replace(item.copyWith(status: 'pending'));
      }
    }
    await _save();
    notifyListeners();
  }

  /// Moves a dismissed / "already logged" item back to review.
  Future<void> restore(String id) async {
    final item = byId(id);
    if (item == null) return;
    _replace(item.copyWith(status: 'pending'));
    await _save();
    notifyListeners();
  }

  Future<void> setCategory(String id, String category) async {
    final item = byId(id);
    if (item == null) return;
    _replace(item.copyWith(category: category));
    await _save();
    notifyListeners();
  }

  /// After "Edit & add" saved an expense tagged 'cap-<id>'.
  Future<void> markAddedFromEditor(String id) async {
    final item = byId(id);
    if (item == null) return;
    for (final e in _expenses!.expenses) {
      if (e.transactionId == 'cap-$id') {
        if (e.category != item.category) _learn(item.merchant, e.category);
        _replace(item.copyWith(
            status: 'added', entryId: e.id, category: e.category));
        await _save();
        notifyListeners();
        return;
      }
    }
  }

  void _learn(String? merchant, String category) {
    if (merchant == null) return;
    final k = MerchantCategorizer.key(merchant);
    if (k.length < 2) return;
    _rules[k] = category;
    _saveRules();
  }

  // --------------------------------------------------------- bank accounts

  /// (pattern, account name, name keys for matching existing accounts, card)
  /// Order matters: "SBI Card" before "SBI", payments banks before "Paytm".
  static final List<(RegExp, String, List<String>, bool)> _banks = [
    (RegExp(r'\bsbi\s*card\b|\bsbicrd\b', caseSensitive: false), 'SBI Card', ['sbicard', 'sbi'], true),
    (RegExp(r'\bpaytm\s*payments?\s*bank\b', caseSensitive: false), 'Paytm Payments Bank', ['paytm'], false),
    (RegExp(r'\bairtel\s*payments?\s*bank\b', caseSensitive: false), 'Airtel Payments Bank', ['airtel'], false),
    (RegExp(r'\bhdfc\b', caseSensitive: false), 'HDFC Bank', ['hdfc'], false),
    (RegExp(r'\bicici\b', caseSensitive: false), 'ICICI Bank', ['icici'], false),
    (RegExp(r'\baxis\b', caseSensitive: false), 'Axis Bank', ['axis'], false),
    (RegExp(r'\bkotak\b', caseSensitive: false), 'Kotak Bank', ['kotak'], false),
    (RegExp(r'\bsbi\b|\bstate\s*bank\s*of\s*india\b', caseSensitive: false), 'SBI', ['sbi', 'statebank'], false),
    (RegExp(r'\bpnb\b|\bpunjab\s*national\b', caseSensitive: false), 'PNB', ['pnb', 'punjabnational'], false),
    (RegExp(r'\bbob\b|\bbank\s*of\s*baroda\b', caseSensitive: false), 'Bank of Baroda', ['baroda', 'bob'], false),
    (RegExp(r'\bcanara\b', caseSensitive: false), 'Canara Bank', ['canara'], false),
    (RegExp(r'\bidfc\b', caseSensitive: false), 'IDFC First Bank', ['idfc'], false),
    (RegExp(r'\bunion\s*bank\b', caseSensitive: false), 'Union Bank', ['union'], false),
    (RegExp(r'\bfederal\s*bank\b', caseSensitive: false), 'Federal Bank', ['federal'], false),
    (RegExp(r'\byes\s*bank\b', caseSensitive: false), 'Yes Bank', ['yesbank'], false),
    (RegExp(r'\bindusind\b', caseSensitive: false), 'IndusInd Bank', ['indusind'], false),
    (RegExp(r'\bau\s*(small\s*finance\s*)?bank\b', caseSensitive: false), 'AU Bank', ['aubank', 'ausmall'], false),
    (RegExp(r'\bidbi\b', caseSensitive: false), 'IDBI Bank', ['idbi'], false),
    (RegExp(r'\bindian\s*overseas\b|\biob\b', caseSensitive: false), 'IOB', ['iob', 'indianoverseas'], false),
    (RegExp(r'\bindian\s*bank\b', caseSensitive: false), 'Indian Bank', ['indianbank'], false),
    (RegExp(r'\buco\b', caseSensitive: false), 'UCO Bank', ['uco'], false),
    (RegExp(r'\bcentral\s*bank\b', caseSensitive: false), 'Central Bank', ['centralbank'], false),
    (RegExp(r'\bciti(bank)?\b', caseSensitive: false), 'Citi', ['citi'], false),
    (RegExp(r'\bhsbc\b', caseSensitive: false), 'HSBC', ['hsbc'], false),
    (RegExp(r'\brbl\b', caseSensitive: false), 'RBL Bank', ['rbl'], false),
  ];
  static final _creditCard = RegExp(r'\bcredit\s*card\b', caseSensitive: false);

  /// Which of *your* banks/cards the payment came from, if the message says.
  /// Payee UPI handles ("swiggy@icici") and UPI paths are ignored so the
  /// payee's bank is never mistaken for yours.
  static (String, List<String>, bool)? _detectBank(DetectedTransaction item) {
    final text = item.rawText
        .replaceAll(RegExp(r'\S+@\S+'), ' ')
        .replaceAll(RegExp(r'\b(?:upi|imps|neft)\/\S+', caseSensitive: false), ' ');
    final sources = [
      if (item.sourceKind == 'sms' && item.appLabel != 'Bank SMS') item.appLabel,
      text,
    ];
    for (final src in sources) {
      for (final b in _banks) {
        if (b.$1.hasMatch(src)) {
          return (b.$2, b.$3, b.$4 || _creditCard.hasMatch(text));
        }
      }
    }
    return null;
  }

  /// The account to log this payment against: an existing account for that
  /// bank (card vs bank account, last 4 digits as tie-breaker), a newly
  /// created one if you don't have it yet, or your default account when the
  /// message doesn't name a bank.
  Future<String?> _resolveAccount(DetectedTransaction item) async {
    final ep = _expenses!;
    final bank = _detectBank(item);
    if (bank == null) return ep.defaultAccount?.id;
    final (bankName, keys, isCard) = bank;

    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final candidates = ep.accounts
        .where((a) => keys.any((k) => norm(a.name).contains(k)))
        .where((a) => a.isCreditCard == isCard)
        .toList();
    if (candidates.isNotEmpty) {
      if (item.last4 != null) {
        for (final a in candidates) {
          if (a.name.contains(item.last4!)) return a.id;
        }
      }
      return candidates.first.id;
    }

    final account = BankAccount(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: isCard && !bankName.endsWith('Card')
          ? '$bankName Credit Card'
          : bankName,
      isDefault: ep.accounts.isEmpty,
      type: isCard ? AccountType.creditCard : AccountType.savings,
    );
    await ep.addAccount(account);
    return account.id;
  }

  /// Account for the "Edit" flow (creates it if needed, like Add does).
  Future<String?> accountFor(String id) async {
    final item = byId(id);
    return item == null ? _expenses?.defaultAccount?.id : _resolveAccount(item);
  }

  // ---------------------------------------------------------------- labels

  static const _appLabels = {
    'com.phonepe.app': 'PhonePe',
    'com.google.android.apps.nbu.paisa.user': 'Google Pay',
    'net.one97.paytm': 'Paytm',
    'in.org.npci.upiapp': 'BHIM',
    'com.dreamplug.androidapp': 'CRED',
    'in.amazon.mShop.android.shopping': 'Amazon Pay',
    'com.naviapp': 'Navi',
    'com.mobikwik_new': 'MobiKwik',
    'com.freecharge.android': 'Freecharge',
  };

  static const _bankHeaders = {
    'HDFC': 'HDFC Bank', 'SBICRD': 'SBI Card', 'SBI': 'SBI', 'CBSSBI': 'SBI',
    'ICICI': 'ICICI Bank', 'AXIS': 'Axis Bank', 'KOTAK': 'Kotak',
    'PNB': 'PNB', 'BOB': 'Bank of Baroda', 'CANBNK': 'Canara Bank',
    'IDFC': 'IDFC First', 'UNION': 'Union Bank', 'FEDBNK': 'Federal Bank',
    'YESBNK': 'Yes Bank', 'INDUS': 'IndusInd', 'PAYTMB': 'Paytm Bank',
    'AIRBNK': 'Airtel Bank', 'IOB': 'IOB', 'UCO': 'UCO Bank',
    'CITI': 'Citi', 'HSBC': 'HSBC', 'AUBANK': 'AU Bank', 'RBL': 'RBL Bank',
    'IDBI': 'IDBI Bank', 'JUPITER': 'Jupiter', 'FIMONEY': 'Fi',
  };

  static String _label(String kind, String sender) {
    if (kind == 'notification') return _appLabels[sender] ?? 'Payment app';
    // DLT headers look like "VM-HDFCBK" or "JD-SBIUPI-S".
    final parts = sender.toUpperCase().split('-');
    final header = parts.length >= 2 ? parts[1] : parts.first;
    for (final entry in _bankHeaders.entries) {
      if (header.contains(entry.key)) return entry.value;
    }
    return 'Bank SMS';
  }
}
