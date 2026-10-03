// Payment auto-detection end to end, with the native capture queue faked:
// one detected payment per real payment (app alert + bank SMS paired one to
// one), repeats of the same message folded in, one manual entry matching
// one payment, import counts, and backups restored on another phone.
// Run: flutter test test/capture_dedupe_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expensetracker/models/expense_models.dart';
import 'package:expensetracker/providers/capture_provider.dart';
import 'package:expensetracker/providers/expense_provider.dart';
import 'package:expensetracker/services/app_prefs.dart';
import 'package:expensetracker/services/capture/capture_models.dart';
import 'package:expensetracker/services/local_store.dart';

/// Stands in for the Android side: a queue of captured messages that stay
/// pending until marked consumed, and an "inbox" an import reads from.
class _FakeNative {
  final queue = <Map<String, Object?>>[];
  var inbox = <Map<String, Object?>>[];
  bool smsAllowed = true;
  Duration fetchDelay = Duration.zero;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'isNotificationAccessGranted':
        return false;
      case 'hasSmsPermission':
        return smsAllowed;
      case 'fetchPending':
        final limit = (call.arguments as Map)['limit'] as int;
        final batch = queue.take(limit).toList();
        if (fetchDelay > Duration.zero) await Future<void>.delayed(fetchDelay);
        return batch;
      case 'markConsumed':
        final ids = ((call.arguments as Map)['ids'] as List).cast<int>();
        queue.removeWhere((r) => ids.contains(r['id']));
        return null;
      case 'backfillSms':
        final n = inbox.length;
        queue.addAll(inbox);
        inbox = [];
        return n;
      default:
        return null;
    }
  }
}

int _ids = 1;

Map<String, Object?> _rec(String body, DateTime at,
        {String source = 'sms', bool backfill = false, int? id}) =>
    {
      'id': id ?? _ids++,
      'source': source,
      'sender': source == 'notification'
          ? 'com.google.android.apps.nbu.paisa.user'
          : 'VM-HDFCBK',
      'body': body,
      'postedAt': at.millisecondsSinceEpoch,
      'backfill': backfill,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeNative native;
  late ExpenseProvider ep;
  late CaptureProvider cap;
  // A fixed base time an hour ago, so everything stays "today" and past.
  final t0 = DateTime.now().subtract(const Duration(hours: 1));

  Future<void> start({Future<void> Function(int userId)? before}) async {
    SharedPreferences.setMockInitialValues({});
    await LocalStore.initialize();
    await LocalStore.resetAllData();
    await AppPrefs.instance.init();
    final user = await LocalStore.createUser('Test');
    final settings = await LocalStore.createDefaultUserSettings(user.id);
    ep = ExpenseProvider();
    await ep.initializeWithUser(user.id, user.userName, settings);
    if (before != null) await before(user.id);
    cap = CaptureProvider();
    await cap.attach(ep);
  }

  setUp(() {
    native = _FakeNative();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('vyaya_capture'), native.handle);
    messenger.setMockStreamHandler(const EventChannel('vyaya_capture/events'),
        MockStreamHandler.inline(onListen: (_, _) {}));
  });

  Future<void> deliver(List<Map<String, Object?>> records) async {
    native.queue.addAll(records);
    await cap.sync();
  }

  test('app alert + bank SMS make one payment; a second order makes another',
      () async {
    await start();
    await deliver([
      _rec('₹250 paid to Swiggy', t0, source: 'notification'),
      _rec('Rs.250.00 debited from A/c XX1234 to SWIGGY. UPI Ref 612345678901',
          t0.add(const Duration(minutes: 1))),
      // Twenty minutes later, the same amount at the same shop again.
      _rec('₹250 paid to Swiggy', t0.add(const Duration(minutes: 20)),
          source: 'notification'),
      _rec('Rs.250.00 debited from A/c XX1234 to SWIGGY. UPI Ref 612345678902',
          t0.add(const Duration(minutes: 21))),
    ]);
    expect(cap.pending, hasLength(2));
    for (final i in cap.pending) {
      expect(i.sources.toSet(), {'notification', 'sms'});
      expect(i.captureIds, hasLength(2));
    }
  });

  test('the same SMS read live and again by an import is one payment',
      () async {
    await start();
    const body =
        'Rs.450.00 debited from A/c XX1234 to SWIGGY. Avl Bal Rs 25,000.00';
    await deliver([_rec(body, t0)]);
    // The inbox time of an imported copy can be minutes after the live one.
    await deliver(
        [_rec(body, t0.add(const Duration(minutes: 15)), backfill: true)]);
    expect(cap.pending, hasLength(1));
    expect(cap.pending.single.captureIds, hasLength(2));
    expect(cap.pending.single.rawText, body); // text not doubled
  });

  test('the same plain message 50 minutes later is a new payment', () async {
    await start();
    await deliver([
      _rec('₹20 paid to Ramu Tea Stall', t0, source: 'notification'),
      _rec('₹20 paid to Ramu Tea Stall', t0.add(const Duration(minutes: 50)),
          source: 'notification'),
    ]);
    expect(cap.pending, hasLength(2));
  });

  test('one manual entry matches only one detected payment', () async {
    await start();
    await ep.addExpense(Expense(
      amount: 20,
      description: 'Chai',
      category: 'Food',
      date: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    await deliver([
      _rec('Rs.20.00 debited from A/c XX1234 to VPA ramu@ybl. UPI Ref 612345678901 -SBI',
          DateTime.now().subtract(const Duration(minutes: 10)),
          backfill: true),
      _rec('Rs.20.00 debited from A/c XX1234 to VPA ramu@ybl. UPI Ref 612345678902 -SBI',
          DateTime.now().subtract(const Duration(minutes: 5)),
          backfill: true),
    ]);
    expect(cap.duplicates, hasLength(1));
    expect(cap.pending, hasLength(1));
  });

  test('an import while a sync is running reports what it found', () async {
    await start();
    native.fetchDelay = const Duration(milliseconds: 30);
    native.queue.add(_rec(
        'Rs.75.00 debited from A/c XX1234 to ZOMATO. UPI Ref 612345670001',
        t0));
    final running = cap.sync();
    native.inbox = [
      _rec('Rs.99.00 debited from A/c XX1234 to BLINKIT. UPI Ref 612345670002',
          t0.add(const Duration(minutes: 1)),
          backfill: true),
      _rec('Rs.60.00 debited from A/c XX1234 to UBER. UPI Ref 612345670003',
          t0.add(const Duration(minutes: 2)),
          backfill: true),
    ];
    final found = await cap.importSmsSince(t0.subtract(const Duration(days: 1)));
    await running;
    expect(found, greaterThanOrEqualTo(2)); // used to say "none"
    expect(cap.pending, hasLength(3));
  });

  test('a removed payment stays removed when the inbox is read again',
      () async {
    await start();
    const body =
        'Rs.310.00 debited from A/c XX1234 to ZEPTO. UPI Ref 612345670009';
    await deliver([_rec(body, t0)]);
    await cap.removeItems(ids: [cap.pending.single.id]);
    expect(cap.pending, isEmpty);

    // The automatic catch-up reads the same SMS from the inbox.
    await deliver([_rec(body, t0, backfill: true)]);
    expect(cap.pending, isEmpty);

    // An import you ask for brings it back.
    native.inbox = [_rec(body, t0, backfill: true)];
    final found =
        await cap.importSmsSince(t0.subtract(const Duration(days: 1)));
    expect(found, 1);
    expect(cap.pending, hasLength(1));
  });

  test('undo of a removal lets the message be matched as before', () async {
    await start();
    const body =
        'Rs.120.00 debited from A/c XX1234 to OLA. UPI Ref 612345670010';
    await deliver([_rec(body, t0)]);
    final gone = await cap.removeItems(ids: [cap.pending.single.id]);
    await cap.putBack(gone);
    expect(cap.pending, hasLength(1));
    // A re-read copy folds into it instead of being skipped or doubled.
    await deliver([_rec(body, t0, backfill: true)]);
    expect(cap.pending, hasLength(1));
    expect(cap.pending.single.captureIds, hasLength(2));
  });

  test('a backup from another phone keeps working with new messages',
      () async {
    final old = DetectedTransaction(
      id: 'old-1',
      captureIds: [5],
      sourceKind: 'sms',
      appLabel: 'HDFC Bank',
      rawText: 'Rs.75.00 debited from A/c XX1234 to ZOMATO. UPI Ref 612345670001',
      amount: 75,
      isDebit: true,
      merchant: 'Zomato',
      last4: '1234',
      reference: '612345670001',
      occurredAt: t0.subtract(const Duration(days: 5)),
      capturedAt: t0.subtract(const Duration(days: 5)),
      confidence: 1,
      flags: const [],
      category: 'Food',
      fromImport: false,
      status: 'pending',
    );
    await start(before: (userId) async {
      await LocalStore.saveJsonList('detected', [old.toJson()],
          userId: userId);
      await LocalStore.setMeta('capture_install', 'another-phone',
          userId: userId);
    });
    // Its queue ids belonged to the other phone.
    expect(cap.pending.single.captureIds, isEmpty);

    // This phone's queue also hands out id 5, for a different message.
    await deliver([
      _rec('Rs.99.00 debited from A/c XX1234 to BLINKIT. UPI Ref 612345670002',
          t0,
          id: 5),
    ]);
    expect(cap.pending, hasLength(2));
  });
}
