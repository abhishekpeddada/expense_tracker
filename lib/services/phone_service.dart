import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_service.dart';

/// How a call ended up in the log.
enum CallKind { incoming, outgoing, missed, rejected, blocked, voicemail, other }

/// One entry from the system call log.
class CallEntry {
  final int id;
  final String number;

  /// Name the system had cached for the number, when it had one.
  final String? name;
  final CallKind kind;
  final DateTime at;
  final Duration duration;

  const CallEntry({
    required this.id,
    required this.number,
    required this.name,
    required this.kind,
    required this.at,
    required this.duration,
  });

  bool get isMissed => kind == CallKind.missed;

  /// CallLog.Calls type constants, which are plain ints over the channel.
  static CallKind _kind(int type) => switch (type) {
        1 => CallKind.incoming,
        2 => CallKind.outgoing,
        3 => CallKind.missed,
        4 => CallKind.voicemail,
        5 => CallKind.rejected,
        6 => CallKind.blocked,
        _ => CallKind.other,
      };

  static CallEntry fromMap(Map<String, Object?> m) => CallEntry(
        id: (m['id'] as num?)?.toInt() ?? 0,
        number: (m['number'] as String?) ?? '',
        name: (m['name'] as String?)?.trim().isEmpty == true
            ? null
            : m['name'] as String?,
        kind: _kind((m['type'] as num?)?.toInt() ?? 0),
        at: DateTime.fromMillisecondsSinceEpoch(
            (m['date'] as num?)?.toInt() ?? 0),
        duration: Duration(seconds: (m['duration'] as num?)?.toInt() ?? 0),
      );
}

/// Bridge to the native phone layer.
///
/// Placing a call works whether or not this app is the default dialer: with
/// the role it goes through Telecom and our own call screen, without it the
/// system dialer is handed the number.
/// What the carrier's voicemail service reports.
///
/// The recording happens on the operator's side - an unanswered call is
/// diverted there, the caller hears the greeting and the beep, and the
/// network raises a waiting flag on the SIM. None of that is the phone's
/// doing, and a dialer can only report it and dial in.
class Voicemail {
  /// The number to dial to listen. Null when the SIM does not carry one.
  final String? number;

  /// The carrier's own name for it, when it supplies one.
  final String? label;

  /// True when the number came from Settings rather than the SIM.
  final bool isOverride;

  const Voicemail({this.number, this.label, this.isOverride = false});

  bool get isAvailable => number != null && number!.isNotEmpty;
}

class PhoneService {
  static const _channel = MethodChannel('expense_tracker/sms');

  Future<bool> get isDefaultDialer async {
    try {
      return await _channel.invokeMethod<bool>('isDefaultDialer') ?? false;
    } on MissingPluginException {
      return false; // non-Android (tests, desktop preview)
    }
  }

  Future<bool> requestDefaultDialerRole() async {
    try {
      return await _channel.invokeMethod<bool>('requestDefaultDialerRole') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> requestPermissions() async {
    try {
      await _channel.invokeMethod('requestPhonePermissions');
    } on MissingPluginException {
      // ignore off-Android
    }
  }

  Future<bool> call(String number) async {
    try {
      return await _channel
              .invokeMethod<bool>('placeCall', {'number': number}) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<Voicemail> voicemail() async {
    try {
      final m = await _channel
          .invokeMethod<Map<Object?, Object?>>('getVoicemail');
      if (m == null) return const Voicemail();
      final map = m.cast<String, Object?>();
      return Voicemail(
        number: (map['number'] as String?)?.trim().isEmpty == true
            ? null
            : map['number'] as String?,
        label: (map['label'] as String?)?.trim().isEmpty == true
            ? null
            : map['label'] as String?,
      );
    } on MissingPluginException {
      return const Voicemail();
    }
  }

  Future<List<CallEntry>> recentCalls({int limit = 200}) async {
    try {
      final list = await _channel
              .invokeMethod<List<Object?>>('getCallLog', {'limit': limit}) ??
          [];
      return [
        for (final e in list)
          CallEntry.fromMap((e as Map).cast<String, Object?>()),
      ];
    } on MissingPluginException {
      return [];
    }
  }
}

final phoneServiceProvider = Provider<PhoneService>((ref) => PhoneService());

/// Recent calls, refreshed when something asks for them again.
final recentCallsProvider = FutureProvider<List<CallEntry>>(
  (ref) => ref.watch(phoneServiceProvider).recentCalls(),
);

/// The voicemail number to actually dial.
///
/// Some SIMs carry the subscriber's own number in the voicemail field, or
/// nothing at all, so a number set in Settings wins over whatever the SIM
/// reports.
final voicemailProvider = FutureProvider<Voicemail>((ref) async {
  final sim = await ref.watch(phoneServiceProvider).voicemail();
  final override = ref.watch(settingsProvider).voicemailNumber;
  if (override.isEmpty) return sim;
  return Voicemail(
    number: override,
    label: sim.label,
    isOverride: true,
  );
});

/// Whether this app currently holds the dialer role. Polled for the same
/// reason the SMS role is: the system dialog and Settings both change it
/// with no callback.
final isDefaultDialerProvider = StreamProvider<bool>((ref) async* {
  final phone = ref.watch(phoneServiceProvider);
  while (true) {
    yield await phone.isDefaultDialer;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
});
