/// Dart side of Vyaya's native payment capture.
///
/// The Android part (a NotificationListenerService + SMS receiver) runs even
/// when the app is closed and stores matching messages in an on-device queue.
/// The app drains that queue with [fetchPending], processes each message and
/// then calls [markConsumed]. [events] fires whenever something new is queued
/// while the app is running.
library;

import 'package:flutter/services.dart';

class CaptureRecord {
  final int id;

  /// 'notification' or 'sms'
  final String source;

  /// Package name (notifications) or SMS sender header like "VM-HDFCBK".
  final String sender;
  final String body;
  final DateTime postedAt;

  /// True when imported from the SMS inbox rather than received live.
  final bool backfill;

  const CaptureRecord({
    required this.id,
    required this.source,
    required this.sender,
    required this.body,
    required this.postedAt,
    required this.backfill,
  });

  factory CaptureRecord.fromMap(Map<dynamic, dynamic> m) => CaptureRecord(
        id: (m['id'] as num).toInt(),
        source: m['source'] as String? ?? 'sms',
        sender: m['sender'] as String? ?? '',
        body: m['body'] as String? ?? '',
        postedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['postedAt'] as num?)?.toInt() ?? 0),
        backfill: m['backfill'] == true,
      );
}

class VyayaCapture {
  VyayaCapture._();

  static const _method = MethodChannel('vyaya_capture');
  static const _events = EventChannel('vyaya_capture/events');

  static Stream<void>? _stream;

  /// Fires when a new message is captured while the app is running.
  static Stream<void> get events =>
      _stream ??= _events.receiveBroadcastStream().map((_) {}).handleError((_) {});

  static Future<T?> _call<T>(String name, [Map<String, dynamic>? args]) async {
    try {
      return await _method.invokeMethod<T>(name, args);
    } on MissingPluginException {
      return null; // not Android / plugin unavailable
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> isNotificationAccessGranted() async =>
      await _call<bool>('isNotificationAccessGranted') ?? false;

  static Future<void> openNotificationAccessSettings() =>
      _call<void>('openNotificationAccessSettings');

  /// Opens this app's system "App info" page (for "Allow restricted settings").
  static Future<void> openAppDetails() => _call<void>('openAppDetails');

  /// Asks Android to reconnect the listener if the system killed it.
  static Future<void> requestRebind() => _call<void>('requestRebind');

  static Future<bool> hasSmsPermission() async =>
      await _call<bool>('hasSmsPermission') ?? false;

  static Future<List<CaptureRecord>> fetchPending({int limit = 200}) async {
    try {
      final list = await _method
          .invokeListMethod<dynamic>('fetchPending', {'limit': limit});
      return (list ?? const [])
          .map((e) => CaptureRecord.fromMap(e as Map))
          .toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<void> markConsumed(List<int> ids) async {
    if (ids.isEmpty) return;
    await _call<void>('markConsumed', {'ids': ids});
  }

  /// Deletes captures from the native queue entirely, so importing the same
  /// SMS again brings them back.
  static Future<void> forget(List<int> ids) async {
    if (ids.isEmpty) return;
    await _call<void>('forget', {'ids': ids});
  }

  static Future<int> pendingCount() async =>
      await _call<int>('pendingCount') ?? 0;

  /// Imports bank SMS received since [since] into the queue. Every message in
  /// that window is checked; [limit] caps how many payment-like ones are
  /// queued. Returns how many were newly queued.
  static Future<int> backfillSms(DateTime since, {int limit = 5000}) async =>
      await _call<int>('backfillSms', {
        'sinceMillis': since.millisecondsSinceEpoch,
        'limit': limit,
      }) ??
      0;

  /// Show a system notification when something is captured while the app is
  /// closed.
  static Future<void> setNotifierEnabled(bool enabled) =>
      _call<void>('setNotifierEnabled', {'enabled': enabled});

  static Future<void> clearNotifier() => _call<void>('clearNotifier');
}
