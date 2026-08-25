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

  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } on MissingPluginException {
      // ignore off-Android
    }
  }

  Future<void> sendSms({required String to, required String body}) =>
      _channel.invokeMethod('sendSms', {'to': to, 'body': body});

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
        );
        // Category chosen from the notification quick-action.
        final category = m['category'] as String?;
        if (category != null && result.txnId != null) {
          await _db.setCategory(result.txnId!, category);
        }
      } catch (err) {
        debugPrint('Failed to ingest SMS entry: $err');
      }
    }
  }
}

final smsServiceProvider = Provider<SmsService>((ref) {
  final service = SmsService(ref.watch(dbProvider));
  service.init();
  return service;
});

final isDefaultSmsAppProvider = FutureProvider<bool>(
  (ref) => ref.watch(smsServiceProvider).isDefaultSmsApp,
);
