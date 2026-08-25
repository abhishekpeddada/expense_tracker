import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../parsing/sms_parser.dart';
import 'db.dart';

final dbProvider = Provider<AppDb>((ref) {
  final db = AppDb();
  ref.onDispose(db.close);
  return db;
});

final transactionsProvider = StreamProvider<List<Transaction>>(
  (ref) => ref.watch(dbProvider).watchTransactions(),
);

final uncategorizedProvider = StreamProvider<List<Transaction>>(
  (ref) => ref.watch(dbProvider).watchUncategorized(),
);

final messagesProvider = StreamProvider<List<SmsMessage>>(
  (ref) => ref.watch(dbProvider).watchMessages(),
);

class IngestResult {
  final ParsedTransaction? parsed;

  /// DB id of the inserted transaction, when the SMS parsed as one.
  final int? txnId;
  const IngestResult(this.parsed, this.txnId);
}

/// Ingests an incoming SMS: stores it for the Messages tab and, when it
/// parses as a transaction, records the transaction as uncategorized.
Future<IngestResult> ingestSms(
  AppDb db, {
  required String sender,
  required String body,
  DateTime? receivedAt,
  String? smsEntryId,
}) async {
  final at = receivedAt ?? DateTime.now();
  final parsed = SmsParser.parse(body, sender: sender);

  await db.insertMessage(SmsMessagesCompanion.insert(
    sender: sender,
    body: body,
    receivedAt: at,
    isTransaction: Value(parsed != null),
  ));

  int? txnId;
  if (parsed != null) {
    txnId = await db.insertTransaction(TransactionsCompanion.insert(
      amount: parsed.amount,
      type: parsed.type,
      accountKind: parsed.accountKind,
      accountTail: Value(parsed.accountTail),
      merchant: Value(parsed.merchant),
      bank: Value(parsed.bank),
      rawSms: Value(body),
      smsSender: Value(sender),
      smsEntryId: Value(smsEntryId),
      occurredAt: at,
    ));
  }
  return IngestResult(parsed, txnId);
}
