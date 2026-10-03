import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vyaya_capture/vyaya_capture.dart';

import '../models/expense_models.dart';
import '../services/capture/capture_models.dart';
import '../services/capture/merchant_categorizer.dart';
import '../services/capture/transaction_parser.dart';
import '../services/app_prefs.dart';
import '../services/local_store.dart';
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
  static const _mutesKey = 'capture_mutes';
  static const _installKey = 'capture_install';
  static const _smsSeenKey = 'capture_sms_seen';
  // This phone only: messages of payments you removed, so the automatic
  // inbox catch-up doesn't bring them back.
  static const _removedKey = 'capture_removed';
  static const _maxItems = 600;

  ExpenseProvider? _expenses;
  StreamSubscription<void>? _eventSub;
  Future<void>? _syncRun;
  bool _resyncRequested = false;

  /// Messages of removed payments: (when it came in ms, its text). Read
  /// from storage on first use.
  List<(int, String)>? _removed;

  /// Counts every new item ever made (for "Found N payments" after an
  /// import; merged repeats don't count).
  int _newItems = 0;

  final List<DetectedTransaction> _items = [];
  final Map<String, String> _rules = {};
  final List<MuteRule> _mutes = [];
  String _mode = 'ask';
  bool _notificationAccess = false;
  bool _smsPermission = false;

  // ---------------------------------------------------------------- getters

  bool get autoMode => _mode == 'auto';
  bool get notificationAccess => _notificationAccess;
  bool get smsPermission => _smsPermission;
  bool get isEnabled => _notificationAccess || _smsPermission;
  List<MuteRule> get muteRules => List.unmodifiable(_mutes);

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
    // Reading the inbox after a long gap can take a moment: done in the
    // background so the app opens right away.
    unawaited(() async {
      try {
        await _catchUpSms();
        await sync();
      } catch (e) {
        debugPrint('SMS catch-up failed: $e');
      }
    }());
  }

  /// The app is back in front: permissions may have changed in system
  /// settings, Android may have disconnected the notification reader
  /// (battery savers do), and payments may be waiting.
  Future<void> onResume() async {
    if (_expenses == null) return;
    await refreshStatus();
    if (_notificationAccess) await VyayaCapture.requestRebind();
    await _catchUpSms();
    await sync();
  }

  /// Bank SMS that arrived while Android had Vyaya fully stopped (some
  /// battery savers do that) never reach the live receiver. They're read
  /// from the inbox instead: everything since the last check, at most 30
  /// days back. Like an import, they wait for review; copies of messages
  /// already caught live are recognised and folded in.
  Future<void> _catchUpSms() async {
    if (!_smsPermission || _userId == 0) return;
    final now = DateTime.now();
    final last = int.tryParse(LocalStore.getDeviceValue(_smsSeenKey) ?? '');
    final stamp = '${now.millisecondsSinceEpoch}';
    if (last == null) {
      // First time: nothing to catch up on.
      await LocalStore.setDeviceValue(_smsSeenKey, stamp);
      return;
    }
    // A little overlap, so a message arriving during the last check isn't
    // missed (a repeat is folded in, not added twice).
    var since = DateTime.fromMillisecondsSinceEpoch(last)
        .subtract(const Duration(minutes: 2));
    final floor = now.subtract(const Duration(days: 30));
    if (since.isBefore(floor)) since = floor;
    if (since.isBefore(now)) {
      final queued = await VyayaCapture.tryBackfillSms(since, limit: 1000000);
      if (queued == null) {
        debugPrint('SMS catch-up failed; will retry next time');
        return;
      }
    }
    // Saved only once the inbox was read: if reading failed, the next
    // check covers this time again.
    await LocalStore.setDeviceValue(_smsSeenKey, stamp);
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
    _hintCache.clear();
    _removed = null; // storage may have been reset or restored
    if (_userId == 0) return;
    final raw = await LocalStore.getJsonList(_itemsKey, userId: _userId);
    _items
      ..clear()
      ..addAll(raw.map(DetectedTransaction.fromJson));
    // Items restored from a backup made on another phone (or before a
    // reinstall) carry that install's message-queue ids, which point at
    // unrelated messages here: drop them. Lists saved before this check
    // existed are taken as this phone's.
    final install = LocalStore.installId();
    final stamp = LocalStore.getMeta(_installKey, userId: _userId);
    if (stamp != install) {
      if (stamp != null) {
        for (var i = 0; i < _items.length; i++) {
          if (_items[i].captureIds.isNotEmpty) {
            _items[i] = _items[i].copyWith(captureIds: const []);
          }
        }
        await _save();
      }
      await LocalStore.setMeta(_installKey, install, userId: _userId);
    }
    _rules.clear();
    final rules = LocalStore.getMeta(_rulesKey, userId: _userId);
    if (rules != null) {
      try {
        _rules.addAll(Map<String, String>.from(jsonDecode(rules) as Map));
      } catch (_) {}
    }
    _mode = LocalStore.getMeta(_modeKey, userId: _userId) ?? 'ask';
    _mutes.clear();
    final mutes = LocalStore.getMeta(_mutesKey, userId: _userId);
    if (mutes != null) {
      try {
        _mutes.addAll((jsonDecode(mutes) as List)
            .map((e) => MuteRule.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {}
    }
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
    await LocalStore.saveJsonList(
        _itemsKey, _items.map((i) => i.toJson()).toList(),
        userId: _userId);
  }

  Future<void> _saveMutes() => LocalStore.setMeta(
      _mutesKey, jsonEncode(_mutes.map((m) => m.toJson()).toList()),
      userId: _userId);

  Future<void> _saveRules() => LocalStore.setMeta(
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
    await LocalStore.setMeta(_modeKey, _mode, userId: _userId);
    notifyListeners();
  }

  /// Imports bank SMS from the last [days] days into the review list.
  /// Imported items are never auto-added. Returns how many new items appeared.
  Future<int> importRecentSms({int days = 30}) =>
      importSmsSince(DateTime.now().subtract(Duration(days: days)));

  /// Imports bank SMS received on or after [since].
  Future<int> importSmsSince(DateTime since) async {
    if (!_smsPermission && !await requestSmsPermission()) return 0;
    final before = _newItems;
    // Asked for on purpose: payments removed from this period come back.
    await _forgetRemovedSince(since);
    // Bounded by date. The native side counts EVERY inbox SMS against this
    // limit (not just payment ones), so it's set far above any real inbox:
    // 3 months with 10,000 messages are all checked, none skipped.
    await VyayaCapture.backfillSms(since, limit: 1000000);
    // Waits for a sync that's already running too (it picks these up).
    await sync();
    return _newItems - before;
  }

  // ------------------------------------------------------------------ sync

  /// Drains the native queue. Safe to call often (app resume, events).
  /// When a sync is already running, this one asks it for another pass and
  /// waits for it, so the caller's messages are in when it returns.
  Future<void> sync() async {
    if (_expenses == null || _userId == 0) return;
    if (_syncRun != null) {
      _resyncRequested = true;
      // Waits for any run that starts right after too (another waiter may
      // start it), so this caller's messages are in when it returns.
      for (var r = _syncRun; r != null; r = _syncRun) {
        await r;
      }
      // The last run finished just before seeing the request: run again.
      if (_resyncRequested) await sync();
      return;
    }
    final run = _drain();
    _syncRun = run;
    try {
      await run;
    } finally {
      if (identical(_syncRun, run)) _syncRun = null;
    }
  }

  Future<void> _drain() async {
    try {
      do {
        _resyncRequested = false;
        // Up to 10,000 per pass (a 30-day import can queue a few thousand).
        for (var round = 0; round < 50; round++) {
          final batch = await VyayaCapture.fetchPending(limit: 200);
          if (batch.isEmpty) break;
          final parsed = await _parseAll(batch);
          for (var i = 0; i < batch.length; i++) {
            // One bad message is skipped, never blocking the rest.
            try {
              await _ingest(batch[i], parsed[i]);
            } catch (e) {
              debugPrint('Skipped a captured message: $e');
            }
            // Let a frame through now and then, so a big import doesn't
            // freeze the screen.
            if (i % 25 == 24) await Future<void>.delayed(Duration.zero);
          }
          await _save();
          // Written to storage before acknowledging, so nothing is lost if
          // the app is closed right now (crash-safe).
          await LocalStore.flush();
          await VyayaCapture.markConsumed(batch.map((r) => r.id).toList());
          notifyListeners();
        }
        await VyayaCapture.clearNotifier();
      } while (_resyncRequested);
    } catch (e) {
      debugPrint('Capture sync failed: $e');
    } finally {
      notifyListeners();
    }
  }

  /// Reads the messages. A larger batch (an SMS import) is read on a
  /// background isolate so the screen stays smooth; a few live messages are
  /// read right here (starting an isolate would cost more).
  static Future<List<ParseResult>> _parseAll(List<CaptureRecord> batch) {
    final jobs = [
      for (final r in batch)
        (
          r.body,
          r.source == 'notification' ? 'notification' : 'sms',
          r.sender,
          r.postedAt,
        ),
    ];
    ParseResult one((String, String, String, DateTime) j) {
      try {
        return TransactionParser.parse(j.$1,
            source: j.$2, sender: j.$3, postedAt: j.$4);
      } catch (_) {
        return ParseResult.reject('error');
      }
    }

    List<ParseResult> run() => [for (final j in jobs) one(j)];
    if (jobs.length < 20) return Future.value(run());
    return Isolate.run(run);
  }

  Future<void> _ingest(CaptureRecord r, ParseResult result) async {
    // Already processed (the queue handed it out again). The text is
    // compared too: after a restore on a new phone, an old item's queue id
    // can belong to a different message.
    if (_items.any((i) => i.captureIds.contains(r.id) && _hasBody(i, r.body))) {
      return;
    }
    final kind = r.source == 'notification' ? 'notification' : 'sms';
    final t = result.transaction;
    if (t == null) return;

    // Removed by you, and read again by the automatic inbox catch-up.
    if (r.backfill &&
        _wasRemoved(r,
            unique: t.reference != null || _uniqueText.hasMatch(r.body))) {
      return;
    }

    // 0) An "Always ignore" rule covers this payee or sender.
    final senderKey = _senderKey(kind, r.sender);
    if (_isMuted(merchant: t.merchant, sender: senderKey)) return;

    // 1) The same payment reported by another source (or re-read)?
    final same = _findSamePayment(t, kind, r.postedAt,
        body: r.body, backfill: r.backfill);
    if (same != null) {
      await _merge(same, t, r, kind);
      return;
    }

    // 2) Already logged by hand?
    final manualId = _findManualEntry(t, r.postedAt, lenient: r.backfill);

    final category = MerchantCategorizer.suggest(
      merchant: t.merchant,
      rawText: r.body,
      categoryNames: _expenses!.categories.map((c) => c.name).toList(),
      learned: _activeRules,
      aliases: _categoryAliases(),
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
      sender: senderKey,
    );
    _items.add(item);
    _newItems++;

    if (item.isPending && _shouldAutoAdd(item)) {
      await _addToLedger(item);
    }
  }

  /// Flags that always need a human look: own-account transfers and card
  /// bill payments aren't new spending, reversals may pair with an earlier
  /// entry, and links may be scams.
  static const _reviewFlags = {'transfer', 'card-bill', 'reversal', 'link'};

  bool _shouldAutoAdd(DetectedTransaction i) =>
      autoMode &&
      !i.fromImport &&
      i.confidence >= 0.8 &&
      !i.flags.any(_reviewFlags.contains);

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

  /// Both names are the same shop: the app says "Swiggy", the bank prints
  /// the company "BUNDL TECHNOLOGIES" (or just "Bundl").
  static bool _sameBrand(String a, String b) {
    final ka = MerchantCategorizer.brandKey(a);
    return ka.length >= 2 && ka == MerchantCategorizer.brandKey(b);
  }

  /// Same payee by name, or the same shop under two names.
  static bool _samePayee(String? a, String? b) =>
      _merchantsMatch(a, b) ||
      (a != null && b != null && _sameBrand(a, b));

  static bool _merchantsMatch(String? a, String? b) {
    if (a == null || b == null) return false;
    final x = MerchantCategorizer.key(a);
    final y = MerchantCategorizer.key(b);
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    if (x.length < 4 || y.length < 4) return false;
    return x.contains(y) || y.contains(x);
  }

  /// [body] is one of the messages folded into [i] (they're joined with a
  /// blank line).
  static bool _hasBody(DetectedTransaction i, String body) =>
      '\n\n${i.rawText}\n\n'.contains('\n\n$body\n\n');

  /// A bank's own transaction number (12-digit UTR / RRN). Two different
  /// ones always mean two payments; other references (an app's order or
  /// transaction id) can't be compared with the bank's.
  static bool _isUtr(String ref) => RegExp(r'^\d{12}$').hasMatch(ref);

  /// Text that only one message can have: a reference number, a balance or
  /// a clock time. Identical text with one of these is the same message.
  static final _uniqueText = RegExp(
      r'\b(?:avl|avbl|available|bal|balance)\b|\b\d{1,2}:\d{2}\b',
      caseSensitive: false);

  /// How far apart the very same text can arrive and still be one message
  /// read twice (a re-posted notification; an SMS caught live and again by
  /// an import, whose inbox time can be well after the live one):
  /// - a bank SMS with a reference / balance / time in it: 3 days;
  /// - a live copy and an imported copy of a plain SMS: 6 hours;
  /// - otherwise 10 minutes (the same plain "₹20 paid to Ramu Tea Stall"
  ///   later on is a new payment).
  static Duration _repeatWindow(
      DetectedTransaction i, String kind, bool backfill, bool unique) {
    if (kind == 'sms') {
      if (unique) return const Duration(days: 3);
      if (i.fromImport != backfill) return const Duration(hours: 6);
    }
    return const Duration(minutes: 10);
  }

  /// The item this report belongs to, if it's a payment already seen:
  /// 1. the very same message again (see [_repeatWindow]), the closest one
  ///    in time;
  /// 2. otherwise the best-matching item for the same amount + direction
  ///    (see [_pairScore]).
  DetectedTransaction? _findSamePayment(
      ParsedTransaction t, String kind, DateTime capturedAt,
      {required String body, required bool backfill}) {
    final horizon = capturedAt.subtract(const Duration(days: 14));
    final unique = t.reference != null || _uniqueText.hasMatch(body);
    DetectedTransaction? repeat;
    Duration? repeatGap;
    DetectedTransaction? best;
    var bestScore = double.negativeInfinity;
    for (final i in _items) {
      if (i.capturedAt.isBefore(horizon)) continue;
      if ((i.amount - t.amount).abs() > 0.009 || i.isDebit != t.isDebit) {
        continue;
      }
      final gap = i.capturedAt.difference(capturedAt).abs();
      if (_hasBody(i, body)) {
        if (gap <= _repeatWindow(i, kind, backfill, unique) &&
            (repeatGap == null || gap < repeatGap)) {
          repeat = i;
          repeatGap = gap;
        }
        // The same text is never a second, different report of a payment.
        continue;
      }
      final score = _pairScore(i, t, kind, gap);
      if (score != null && score > bestScore) {
        best = i;
        bestScore = score;
      }
    }
    return repeat ?? best;
  }

  /// How well a new report matches item [i] (higher is better), or null
  /// when it's a different payment. Each item takes at most one report of
  /// each kind (one app notification, one bank SMS), so two real payments
  /// of the same amount never end up as one, however close in time.
  /// - Matching references: the same payment.
  /// - Two different bank references (UTRs), or two different references
  ///   from the same kind of source: two payments.
  /// - Two different named payees, or different account / card digits:
  ///   two payments ("BUNDL TECHNOLOGIES" and "Swiggy" are the same shop).
  /// - The other kind of report: within 5 min; within 30 min when one of
  ///   them has no payee (e.g. the app only named a QR handle); within 3 h
  ///   with the same payee.
  /// - The same kind again: only a quick re-post (within 2 min, slightly
  ///   different text, not both nameless: two nameless QR payments are two
  ///   payments).
  static double? _pairScore(
      DetectedTransaction i, ParsedTransaction t, String kind, Duration gap) {
    final mins = gap.inSeconds / 60;
    if (_refsMatch(i.reference, t.reference)) return 1000 - mins / 1000;
    final sameKind = i.sources.contains(kind);
    if (i.reference != null && t.reference != null) {
      if (_isUtr(i.reference!) && _isUtr(t.reference!)) return null;
      if (sameKind) return null;
    }
    if (i.merchant != null &&
        t.merchant != null &&
        !_samePayee(i.merchant, t.merchant)) {
      return null;
    }
    if (i.last4 != null &&
        t.allLast4.isNotEmpty &&
        !t.allLast4.contains(i.last4)) {
      return null;
    }
    final samePayee = _samePayee(i.merchant, t.merchant);
    final nameless = i.merchant == null || t.merchant == null;
    if (sameKind) {
      if (gap <= const Duration(minutes: 2) &&
          !(i.merchant == null && t.merchant == null)) {
        return 100 - mins / 10;
      }
      return null;
    }
    if (gap <= const Duration(minutes: 5)) {
      return (samePayee ? 300 : 200) - mins / 10;
    }
    // Bank SMS often arrive late; a nameless report can't contradict.
    if (gap <= const Duration(minutes: 30) && nameless) return 150 - mins / 10;
    if (gap <= const Duration(hours: 3) && samePayee) return 250 - mins / 10;
    return null;
  }

  /// An expense/income the user logged themselves for this payment.
  /// Live: logged within 30 min, or same day with the same payee.
  /// Import (lenient): same amount on the same day.
  /// One entry stands for one payment, so entries another detected payment
  /// already matched are skipped; among the rest the best match wins (same
  /// payee first, then logged closest in time).
  String? _findManualEntry(ParsedTransaction t, DateTime capturedAt,
      {required bool lenient}) {
    final ep = _expenses!;
    final claimed = {
      for (final i in _items)
        if (i.status == 'duplicate' && i.entryId != null) i.entryId!,
    };
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    String? bestId;
    var bestNamed = false;
    Duration? bestGap;
    void consider(String? id, DateTime created, DateTime date, String? name) {
      if (id == null || claimed.contains(id)) return;
      final gap = created.difference(capturedAt).abs();
      final named = _merchantsMatch(name, t.merchant);
      final close = gap <= const Duration(minutes: 30);
      if (!close && !(sameDay(date, t.occurredAt) && (lenient || named))) {
        return;
      }
      final better = bestId == null ||
          (named && !bestNamed) ||
          (named == bestNamed && gap < bestGap!);
      if (better) {
        bestId = id;
        bestNamed = named;
        bestGap = gap;
      }
    }

    if (t.isDebit) {
      for (final e in ep.expenses) {
        if ((e.amount - t.amount).abs() > 0.009) continue;
        final tid = e.transactionId ?? '';
        if (tid.startsWith('cap-') || tid.startsWith('auto-saved-')) continue;
        consider(e.id, e.createdAt, e.date, e.description);
      }
    } else {
      for (final inc in ep.incomes) {
        if ((inc.amount - t.amount).abs() > 0.009) continue;
        if ((inc.notes ?? '').startsWith('Auto-detected')) continue;
        consider(inc.id, inc.createdAt, inc.date, inc.title);
      }
    }
    return bestId;
  }

  /// Folds a second report of the same payment into the existing item,
  /// filling in anything it was missing (payee, account, reference). The
  /// same message read again only has its queue id noted.
  Future<void> _merge(DetectedTransaction existing, ParsedTransaction t,
      CaptureRecord r, String kind) async {
    final idx = _items.indexWhere((i) => i.id == existing.id);
    if (idx == -1) return;
    if (_hasBody(existing, r.body)) {
      _items[idx] = existing.copyWith(
          captureIds: [...existing.captureIds, r.id]);
      return;
    }
    final gainedMerchant = existing.merchant == null && t.merchant != null;
    var updated = existing.copyWith(
      captureIds: [...existing.captureIds, r.id],
      sources: existing.sources.contains(kind)
          ? existing.sources
          : [...existing.sources, kind],
      rawText: '${existing.rawText}\n\n${r.body}',
      merchant: existing.merchant ?? t.merchant,
      last4: existing.last4 ?? t.last4,
      reference: existing.reference ?? t.reference,
      // Keep warnings from either report (e.g. the app's "paid to CRED"
      // marks the bank's plain debit as a card bill).
      flags: {...existing.flags, ...t.flags}.toList(),
    );
    // Re-guess the category from the newly known payee, but only if it's
    // still Vyaya's own fallback guess: a category you picked stays.
    final names = _expenses!.categories.map((c) => c.name).toList();
    if (gainedMerchant &&
        existing.isPending &&
        existing.category == MerchantCategorizer.fallbackCategory(names)) {
      updated = updated.copyWith(
        category: MerchantCategorizer.suggest(
          merchant: t.merchant,
          rawText: r.body,
          categoryNames: _expenses!.categories.map((c) => c.name).toList(),
          learned: _activeRules,
          aliases: _categoryAliases(),
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

  /// Payments being added right now ("Add all", a swipe and auto-add can
  /// overlap): each one is added once.
  final Set<String> _adding = {};

  Future<void> _addToLedger(DetectedTransaction item, {String? category}) async {
    if (!_adding.add(item.id)) return;
    try {
      if (byId(item.id)?.status == 'added') return;
      await _addToLedgerNow(item, category: category);
    } finally {
      _adding.remove(item.id);
    }
  }

  Future<void> _addToLedgerNow(DetectedTransaction item,
      {String? category}) async {
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
    // The latest copy: a repeat message may have been folded in meanwhile.
    _replace((byId(item.id) ?? item)
        .copyWith(status: 'added', category: cat, entryId: entryId));
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

  /// Adds every pending payment except likely transfers and card bill
  /// payments, which stay in review (adding them would double count).
  /// Returns how many were added and how many were left.
  /// [only] limits it to those ids. [skipFlagged] false adds transfers and
  /// card bills too (the user picked them explicitly).
  Future<({int added, int skipped, List<String> ids})> acceptAll(
      {Iterable<String>? only, bool skipFlagged = true}) async {
    final wanted = only?.toSet();
    final addedIds = <String>[];
    var skipped = 0;
    for (final item in pending) {
      if (wanted != null && !wanted.contains(item.id)) continue;
      if (skipFlagged && item.flags.any(_notSpendingFlags.contains)) {
        skipped++;
        continue;
      }
      await _addToLedger(item);
      addedIds.add(item.id);
    }
    await _save();
    notifyListeners();
    return (added: addedIds.length, skipped: skipped, ids: addedIds);
  }

  /// Undo for adding: removes the expense/income it created and puts the
  /// payment back in review.
  Future<void> unaccept(String id) => unacceptMany([id]);

  Future<void> unacceptMany(List<String> ids) async {
    final ep = _expenses;
    if (ep == null) return;
    for (final id in ids) {
      final item = byId(id);
      if (item == null || item.status != 'added') continue;
      final entry = item.entryId;
      if (entry != null) {
        try {
          if (item.isDebit) {
            await ep.deleteExpense(entry);
          } else {
            await ep.deleteIncome(entry);
          }
        } catch (e) {
          debugPrint('Undo add failed for $id: $e');
        }
      }
      _replace(item.copyWith(status: 'pending'));
    }
    await _save();
    notifyListeners();
  }

  /// Removes detected payments from the list for good. Expenses and income
  /// they already created stay. [ids] limits it to those; otherwise it's
  /// everything waiting for review, or the whole list with [everything].
  /// Their messages are forgotten natively too, so importing that period
  /// again brings them back. Returns what was removed (for undo).
  Future<List<DetectedTransaction>> removeItems(
      {Iterable<String>? ids, bool everything = false}) async {
    final wanted = ids?.toSet();
    final removed = _items
        .where((i) =>
            wanted != null ? wanted.contains(i.id) : (everything || i.isPending))
        .toList();
    if (removed.isEmpty) return removed;
    final gone = removed.map((i) => i.id).toSet();
    _items.removeWhere((i) => gone.contains(i.id));
    await _save();
    notifyListeners();
    await _saveRemoved([
      ..._removedList(),
      for (final i in removed)
        if (i.rawText.isNotEmpty)
          (i.capturedAt.millisecondsSinceEpoch, i.rawText),
    ]);
    try {
      await VyayaCapture.forget(
          [for (final i in removed) ...i.captureIds]);
    } catch (e) {
      debugPrint('Forgetting captures failed: $e');
    }
    return removed;
  }

  /// Undo for [removeItems].
  Future<void> putBack(List<DetectedTransaction> items) async {
    for (final i in items) {
      if (byId(i.id) == null) _items.add(i);
    }
    await _save();
    notifyListeners();
    final back = {
      for (final i in items) (i.capturedAt.millisecondsSinceEpoch, i.rawText)
    };
    final list = _removedList();
    if (list.any(back.contains)) {
      await _saveRemoved(list.where((e) => !back.contains(e)).toList());
    }
  }

  // A message can be folded into a payment up to 3 days after the first.
  static const _removedWindowMs = 4 * 24 * 60 * 60 * 1000;

  List<(int, String)> _removedList() {
    final cached = _removed;
    if (cached != null) return cached;
    final list = <(int, String)>[];
    final raw = LocalStore.getDeviceValue(_removedKey);
    if (raw != null) {
      try {
        for (final e in jsonDecode(raw) as List) {
          final pair = e as List;
          list.add(((pair[0] as num).toInt(), pair[1] as String));
        }
      } catch (_) {
        list.clear();
      }
    }
    return _removed = list;
  }

  /// Keeps 35 days: the catch-up never reads further back than 30 (plus
  /// the matching window).
  Future<void> _saveRemoved(List<(int, String)> list) async {
    final floor = DateTime.now()
        .subtract(const Duration(days: 35))
        .millisecondsSinceEpoch;
    final kept = list.where((e) => e.$1 >= floor).toList();
    _removed = kept;
    await LocalStore.setDeviceValue(
        _removedKey, jsonEncode([for (final e in kept) [e.$1, e.$2]]));
  }

  Future<void> _forgetRemovedSince(DateTime since) async {
    final from = since.millisecondsSinceEpoch - _removedWindowMs;
    final list = _removedList();
    if (list.any((e) => e.$1 >= from)) {
      await _saveRemoved(list.where((e) => e.$1 < from).toList());
    }
  }

  /// [unique]: the text can't repeat for another payment (it has a
  /// reference, balance or time). Plain text like "Rs 20 paid to Ramu" can,
  /// so it only counts as the removed message within a few hours.
  bool _wasRemoved(CaptureRecord r, {required bool unique}) {
    final list = _removedList();
    if (list.isEmpty) return false;
    final at = r.postedAt.millisecondsSinceEpoch;
    final window = unique ? _removedWindowMs : 9 * 60 * 60 * 1000;
    final body = '\n\n${r.body}\n\n';
    return list.any((e) =>
        (e.$1 - at).abs() <= window && '\n\n${e.$2}\n\n'.contains(body));
  }

  /// Keeps detected payments and learned payee rules pointing at a category
  /// after it's renamed.
  Future<void> renameCategory(String from, String to) async {
    // "Remember last category" follows the rename / move too.
    await AppPrefs.instance.renameLastCategory(from, to);
    var changed = false;
    for (final i in List.of(_items)) {
      if (i.category == from) {
        _replace(i.copyWith(category: to));
        changed = true;
      }
    }
    var rulesChanged = false;
    for (final k in _rules.keys.toList()) {
      if (_rules[k] == from) {
        _rules[k] = to;
        rulesChanged = true;
      }
    }
    if (changed) await _save();
    if (rulesChanged) await _saveRules();
    if (changed || rulesChanged) notifyListeners();
  }

  /// Default categories renamed by the user: default name -> current name,
  /// so keyword suggestions ("swiggy" -> Food) follow the rename.
  Map<String, String> _categoryAliases() => {
        for (final c in _expenses?.categories ?? const <ExpenseCategory>[])
          c.id: c.name,
      };

  // ------------------------------------------------------------ ignore rules

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// SMS header code ("VM-HDFCBK-S" -> "HDFCBK") or the app package.
  static String? _senderKey(String kind, String? sender) {
    if (sender == null || sender.trim().isEmpty) return null;
    if (kind == 'notification') return sender;
    final parts = sender.toUpperCase().split('-');
    final header = parts.length >= 2 ? parts[1] : parts.first;
    final clean = header.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return clean.isEmpty ? null : clean;
  }

  bool _isMuted({String? merchant, String? sender}) {
    if (_mutes.isEmpty) return false;
    final payee = merchant == null ? '' : _norm(merchant);
    for (final m in _mutes) {
      if (m.isPayee && payee.isNotEmpty && payee == m.value) return true;
      if (!m.isPayee && sender != null && sender == m.value) return true;
    }
    return false;
  }

  bool _matchesMute(MuteRule m, DetectedTransaction i) => m.isPayee
      ? i.merchant != null && _norm(i.merchant!) == m.value
      : i.sender != null && i.sender == m.value;

  /// Rule for "always ignore this payee", or null when it has no payee name.
  MuteRule? payeeRuleFor(DetectedTransaction i) {
    final name = i.merchant;
    if (name == null || _norm(name).isEmpty) return null;
    return MuteRule(type: 'payee', value: _norm(name), label: name);
  }

  /// Rule for "always ignore this sender", or null when the sender is unknown.
  MuteRule? senderRuleFor(DetectedTransaction i) {
    final s = i.sender;
    if (s == null) return null;
    final label = i.sourceKind == 'notification'
        ? i.appLabel
        : (i.appLabel == 'Bank SMS' ? s : '${i.appLabel} ($s)');
    return MuteRule(type: 'sender', value: s, label: label);
  }

  /// Adds a rule and dismisses the matching payments waiting for review.
  /// Returns the ids it dismissed (for undo).
  Future<List<String>> addMute(MuteRule rule) async {
    if (!_mutes.contains(rule)) _mutes.add(rule);
    final hidden = <String>[];
    for (final i in pending) {
      if (_matchesMute(rule, i)) {
        _replace(i.copyWith(status: 'dismissed'));
        hidden.add(i.id);
      }
    }
    await _saveMutes();
    await _save();
    notifyListeners();
    return hidden;
  }

  Future<void> removeMute(MuteRule rule) async {
    _mutes.remove(rule);
    await _saveMutes();
    notifyListeners();
  }

  static const _notSpendingFlags = {'transfer', 'card-bill'};

  Future<void> dismiss(String id) async {
    final item = byId(id);
    if (item == null) return;
    _replace(item.copyWith(status: 'dismissed'));
    await _save();
    notifyListeners();
  }

  /// Dismisses everything waiting for review. Returns their ids (for undo).
  Future<List<String>> dismissAll({Iterable<String>? only}) async {
    final wanted = only?.toSet();
    final ids = pending
        .where((i) => wanted == null || wanted.contains(i.id))
        .map((i) => i.id)
        .toList();
    for (final id in ids) {
      final item = byId(id);
      if (item != null) _replace(item.copyWith(status: 'dismissed'));
    }
    await _save();
    notifyListeners();
    return ids;
  }

  /// Dismisses the given items (undo for "Restore all").
  Future<void> dismissMany(List<String> ids) async {
    for (final id in ids) {
      final item = byId(id);
      if (item != null && item.isPending) {
        _replace(item.copyWith(status: 'dismissed'));
      }
    }
    await _save();
    notifyListeners();
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

  /// Category picked on a payment in the review list. Also remembered for
  /// the payee, so their other waiting payments follow.
  Future<void> setCategory(String id, String category) async {
    final item = byId(id);
    if (item == null) return;
    _replace(item.copyWith(category: category));
    if (item.isDebit) _learn(item.merchant, category);
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

  /// An expense's category was changed later (from its edit screen). If it
  /// came from detection, remember that payee's category and keep the
  /// detected item in step; otherwise learn from the payee typed in.
  Future<void> learnFromEdit(String? transactionId, String category,
      {String? payee}) async {
    String? merchant;
    if (transactionId != null && transactionId.startsWith('cap-')) {
      final item = byId(transactionId.substring(4));
      if (item != null) {
        merchant = item.merchant;
        _replace(item.copyWith(category: category));
        await _save();
      }
    }
    merchant ??= payee;
    if (merchant == null || merchant.trim().isEmpty) return;
    _learn(merchant, category);
    notifyListeners();
  }

  /// Payee rules, or none when "Remember category per payee" is off.
  Map<String, String> get _activeRules =>
      AppPrefs.instance.rememberPayeeCategory ? _rules : const {};

  /// The category last used for [payee], if it still exists (never "Saved",
  /// which isn't picked by hand). Null when the option is off.
  String? categoryForPayee(String payee) {
    final cat = _activeRules[MerchantCategorizer.key(payee)];
    if (cat == null || cat == ExpenseProvider.savedCategoryName) return null;
    final exists = _expenses?.categories.any((c) => c.name == cat) ?? false;
    return exists ? cat : null;
  }

  /// The usual category for a well-known payee ("Swiggy" -> Food), if you
  /// have one for it.
  String? classicCategoryFor(String payee) {
    final group = MerchantCategorizer.groupFor(merchant: payee);
    if (group == null) return null;
    return MerchantCategorizer.categoryFor(group,
        _expenses?.categories.map((c) => c.name).toList() ?? const [],
        _categoryAliases());
  }

  /// A new expense added by hand: remember its payee's category.
  void learnFromManual(String payee, String category) {
    if (category == ExpenseProvider.savedCategoryName) return;
    _learn(payee, category);
  }

  /// Remembers [category] for the payee and moves their other payments
  /// still waiting for review to it (already-added ones are left alone:
  /// the same person can be paid for different things).
  void _learn(String? merchant, String category) {
    if (merchant == null) return;
    if (!AppPrefs.instance.rememberPayeeCategory) return;
    // "Saved" is only for month-end savings, never a payee's category.
    if (category == ExpenseProvider.savedCategoryName) return;
    final k = MerchantCategorizer.key(merchant);
    if (k.length < 2) return;
    // A nameless detected payment's placeholder title isn't a payee.
    if (k == 'upipayment' || k == 'moneyreceived') return;
    _rules[k] = category;
    _saveRules();
    var moved = false;
    for (final i in List.of(_items)) {
      if (i.isPending &&
          i.isDebit &&
          i.category != category &&
          i.merchant != null &&
          MerchantCategorizer.key(i.merchant!) == k) {
        _replace(i.copyWith(category: category));
        moved = true;
      }
    }
    if (moved) {
      _save();
      notifyListeners();
    }
  }

  // ------------------------------------------------- new-category suggestions

  /// "Looks like Gym": the kind of spending a waiting payment belongs to,
  /// when you have no category for it and it's still in "Other". Null when
  /// suggestions are off, dismissed for that kind, or you already chose a
  /// category for this payee.
  CategoryGroup? newCategoryHint(DetectedTransaction item) {
    // Cached per payment until something it depends on changes.
    final prefs = AppPrefs.instance;
    final names = _expenses?.categories.map((c) => c.name).toList() ?? [];
    final stamp = Object.hash(
        item.category,
        item.merchant,
        item.rawText,
        item.status,
        Object.hashAll(names),
        prefs.suggestNewCategories,
        Object.hashAll(prefs.dismissedGroups),
        prefs.rememberPayeeCategory,
        _rules.length);
    final cached = _hintCache[item.id];
    if (cached != null && cached.$1 == stamp) return cached.$2;
    final hint = _computeHint(item);
    _hintCache[item.id] = (stamp, hint);
    return hint;
  }

  final Map<String, (int, CategoryGroup?)> _hintCache = {};

  CategoryGroup? _computeHint(DetectedTransaction item) {
    final prefs = AppPrefs.instance;
    if (!item.isDebit || !item.isPending || !prefs.suggestNewCategories) {
      return null;
    }
    final names = _expenses?.categories.map((c) => c.name).toList() ?? [];
    if (item.category != MerchantCategorizer.fallbackCategory(names)) {
      return null;
    }
    final m = item.merchant;
    if (m != null && _activeRules.containsKey(MerchantCategorizer.key(m))) {
      return null;
    }
    final group =
        MerchantCategorizer.groupFor(merchant: m, rawText: item.rawText);
    if (group == null ||
        !group.offerCreate ||
        prefs.dismissedGroups.contains(group.key) ||
        MerchantCategorizer.categoryFor(group, names, _categoryAliases()) !=
            null) {
      return null;
    }
    return group;
  }

  /// Creates the suggested category (or reuses one with that name) and
  /// re-sorts every waiting payment still in "Other", so all the Nutrabay /
  /// MuscleBlaze ones move to the new "Gym" at once. Returns its name.
  Future<String> createCategoryForGroup(CategoryGroup group) async {
    final ep = _expenses!;
    var name = group.name;
    final same = ep.categories
        .where((c) => c.name.toLowerCase() == group.name.toLowerCase());
    if (same.isNotEmpty) {
      name = same.first.name;
    } else {
      final hex = (group.color & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
      await ep.addCustomCategory(ExpenseCategory(
        id: 'grp_${group.key}_${DateTime.now().millisecondsSinceEpoch}',
        name: group.name,
        icon: group.icon,
        colorHex: '#$hex',
      ));
    }
    final names = ep.categories.map((c) => c.name).toList();
    final fallback = MerchantCategorizer.fallbackCategory(names);
    for (final i in List.of(_items)) {
      if (!i.isPending || !i.isDebit || i.category != fallback) continue;
      final cat = MerchantCategorizer.suggest(
        merchant: i.merchant,
        rawText: i.rawText,
        categoryNames: names,
        learned: _activeRules,
        aliases: _categoryAliases(),
      );
      if (cat != i.category) _replace(i.copyWith(category: cat));
    }
    await _save();
    notifyListeners();
    return name;
  }

  /// "Stop suggesting Gym".
  Future<void> dismissGroup(CategoryGroup group) async {
    await AppPrefs.instance.dismissGroup(group.key);
    notifyListeners();
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
  Future<String?> _resolveAccount(DetectedTransaction item) async =>
      (await _findOrCreateAccount(item)).id;

  Future<({String? id, bool created})> _findOrCreateAccount(
      DetectedTransaction item) async {
    final ep = _expenses!;
    final bank = _detectBank(item);
    if (bank == null) return (id: ep.defaultAccount?.id, created: false);
    final (bankName, keys, isCard) = bank;

    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final candidates = ep.accounts
        .where((a) => keys.any((k) => norm(a.name).contains(k)))
        .where((a) => a.isCreditCard == isCard)
        .toList();
    if (candidates.isNotEmpty) {
      if (item.last4 != null) {
        for (final a in candidates) {
          if (a.name.contains(item.last4!)) return (id: a.id, created: false);
        }
      }
      return (id: candidates.first.id, created: false);
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
    return (id: account.id, created: true);
  }

  /// Account for the "Edit" flow. Creates it if needed (so the editor can
  /// show it); `created` tells the caller to call [discardAccountIfUnused]
  /// afterwards in case the edit is cancelled or another account is picked.
  Future<({String? id, bool created})> accountFor(String id) async {
    final item = byId(id);
    if (item == null) {
      return (id: _expenses?.defaultAccount?.id, created: false);
    }
    return _findOrCreateAccount(item);
  }

  /// Removes an account created by [accountFor] if nothing ended up using it.
  Future<void> discardAccountIfUnused(String accountId) async {
    final ep = _expenses;
    if (ep == null || ep.getAccountById(accountId) == null) return;
    if (ep.accountUsageCount(accountId) == 0) {
      await ep.removeAccount(accountId);
    }
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
