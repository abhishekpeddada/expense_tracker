import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../data/providers.dart';

/// Bridge to the native SMS layer (see android/.../MainActivity.kt).
///
/// Incoming SMS are queued natively (the receiver runs even when Flutter is
/// dead) and drained here into the drift DB. A category picked from the
/// notification's quick-actions rides along with the queued entry.
class SmsService {
  SmsService(this._db);

  final AppDb _db;
  static const _channel = MethodChannel('expense_tracker/sms');

  void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'smsPing') {
        await drainQueue();
      }
    });
  }

  Future<bool> get isDefaultSmsApp async {
    try {
      return await _channel.invokeMethod<bool>('isDefaultSmsApp') ?? false;
    } on MissingPluginException {
      return false; // non-Android (tests, desktop preview)
    }
  }

  Future<bool> requestDefaultSmsRole() async {
    try {
      return await _channel.invokeMethod<bool>('requestDefaultSmsRole') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Requests notification + contacts permissions.
  Future<void> requestPermissions() async {
    try {
      await _channel.invokeMethod('requestPermissions');
    } on MissingPluginException {
      // ignore off-Android
    }
  }

  /// Setup checks (default-app role, permissions, battery state).
  Future<Map<String, bool>> diagnostics() async {
    try {
      final m = await _channel
          .invokeMethod<Map<Object?, Object?>>('getDiagnostics');
      return {
        for (final e in (m ?? {}).entries)
          e.key as String: e.value as bool,
      };
    } on MissingPluginException {
      return {};
    }
  }

  /// What the broadcast receiver logged for incoming SMS.
  Future<List<Map<String, Object?>>> receiveLog() async {
    try {
      final list =
          await _channel.invokeMethod<List<Object?>>('getReceiveLog') ?? [];
      return [
        for (final e in list) (e as Map).cast<String, Object?>(),
      ];
    } on MissingPluginException {
      return [];
    }
  }

  Future<void> clearReceiveLog() async {
    try {
      await _channel.invokeMethod('clearReceiveLog');
    } on MissingPluginException {
      // ignore off-Android
    }
  }

  final _contactCache = <String, String?>{};

  /// Contact display name for a phone number, or null (no permission, no
  /// match, or a shortcode sender like VM-HDFCBK).
  Future<String?> contactName(String number) async {
    if (_contactCache.containsKey(number)) return _contactCache[number];
    String? name;
    try {
      name = await _channel
          .invokeMethod<String>('getContactName', {'number': number});
    } on MissingPluginException {
      name = null;
    }
    _contactCache[number] = name;
    return name;
  }

  Future<void> sendSms({required String to, required String body}) async {
    await _channel.invokeMethod('sendSms', {'to': to, 'body': body});
    await _db.insertMessage(SmsMessagesCompanion.insert(
      sender: to,
      body: body,
      receivedAt: DateTime.now(),
      outgoing: const Value(true),
      read: const Value(true),
    ));
  }

  /// Pulls natively-queued SMS into the DB. Safe to call repeatedly.
  Future<void> drainQueue() async {
    List<Object?> entries;
    try {
      entries =
          await _channel.invokeMethod<List<Object?>>('drainSmsQueue') ?? [];
    } on MissingPluginException {
      return;
    }
    for (final e in entries) {
      final m = (e as Map).cast<String, Object?>();
      try {
        final result = await ingestSms(
          _db,
          sender: m['sender'] as String? ?? 'Unknown',
          body: m['body'] as String? ?? '',
          receivedAt: DateTime.fromMillisecondsSinceEpoch(
              (m['ts'] as num?)?.toInt() ??
                  DateTime.now().millisecondsSinceEpoch),
          smsEntryId: m['id'] as String?,
        );
        // Category chosen from the notification before this entry was
        // drained.
        final category = m['category'] as String?;
        if (category != null && result.txnId != null) {
          await _db.setCategory(result.txnId!, category);
        }
      } catch (err) {
        debugPrint('Failed to ingest SMS entry: $err');
      }
    }
    await _applyPendingCategories();
  }

  /// Applies category picks made on notifications for transactions that were
  /// already drained into the DB (see CategoryActionReceiver.kt).
  Future<void> _applyPendingCategories() async {
    Map<Object?, Object?> pending;
    try {
      pending = await _channel
              .invokeMethod<Map<Object?, Object?>>('getPendingCategories') ??
          {};
    } on MissingPluginException {
      return;
    }
    for (final entry in pending.entries) {
      final entryId = entry.key as String;
      final category = entry.value as String;
      try {
        // Fills in the category only if still uncategorized, then always
        // clears the pending entry — a stale pick must never keep
        // re-applying itself over later in-app changes.
        await _db.setCategoryBySmsEntry(entryId, category);
      } catch (err) {
        debugPrint('Failed to apply pending category: $err');
      }
      await _channel
          .invokeMethod('removePendingCategory', {'entryId': entryId});
    }
  }
}

final smsServiceProvider = Provider<SmsService>((ref) {
  final service = SmsService(ref.watch(dbProvider));
  service.init();
  return service;
});

/// Contact name lookup, cached per number for the app session.
final contactNameProvider = FutureProvider.family<String?, String>(
  (ref, number) => ref.watch(smsServiceProvider).contactName(number),
);

/// Live view of whether we hold the default-SMS-app role. Polled, because
/// the role can change from the system dialog or Settings without any
/// reliable in-app callback.
final isDefaultSmsAppProvider = StreamProvider<bool>((ref) async* {
  final sms = ref.watch(smsServiceProvider);
  while (true) {
    yield await sms.isDefaultSmsApp;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
});
