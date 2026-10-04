import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'openrouter.dart';
import 'settings_service.dart';

/// Turning a shared payment receipt into a transaction.
///
/// Some banks never send an SMS for small UPI debits, so the screenshot a
/// payment app produces is the only record of the payment. Sharing it into
/// this app is the way those get recorded.
class ReceiptImport {
  ReceiptImport(this._ref);

  final Ref _ref;
  static const _channel = MethodChannel('expense_tracker/sms');

  /// Collects an image shared into the app, if one is waiting. Returns it
  /// once: the native side forgets it, so a rebuild cannot reimport the
  /// same receipt twice.
  Future<Uint8List?> takeShared() async {
    try {
      return await _channel.invokeMethod<Uint8List>('takeSharedImage');
    } on MissingPluginException {
      return null;
    }
  }

  bool get isConfigured => _ref.read(openRouterProvider) != null;

  /// Reads the payment out of a receipt image.
  Future<ReceiptReading> read(Uint8List jpeg) async {
    final client = _ref.read(openRouterProvider);
    if (client == null) {
      throw const OpenRouterException(
          'Add an OpenRouter key in Settings to read receipts.');
    }
    return client.readReceipt(jpeg);
  }
}

final receiptImportProvider =
    Provider<ReceiptImport>(ReceiptImport.new);
