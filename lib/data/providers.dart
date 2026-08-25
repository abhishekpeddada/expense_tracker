import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
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

/// A bank account / credit card derived from transaction data. There is no
/// live bank link — accounts appear automatically from parsed SMS and
/// imported statements (grouped by bank + last-4 + kind).
class DerivedAccount {
  final String? bank;
  final String? tail;
  final AccountKind kind;
  final List<Transaction> transactions;

  /// Balance ("Avl bal" / card available limit) from the most recent
  /// transaction that stated one.
  final double? balance;
  final DateTime? balanceAsOf;

  const DerivedAccount({
    required this.bank,
    required this.tail,
    required this.kind,
    required this.transactions,
    this.balance,
    this.balanceAsOf,
  });

  String get title => bank ?? (kind == AccountKind.creditCard ? 'Card' : 'Account');
  DateTime get lastActivity => transactions.first.occurredAt;
}

/// Groups transactions into derived accounts, newest activity first.
/// Transactions with neither a bank nor a last-4 are left out.
final accountsProvider = Provider<List<DerivedAccount>>((ref) {
  final txns = ref.watch(transactionsProvider).valueOrNull ?? [];
  final groups = <String, List<Transaction>>{};
  for (final t in txns) {
    if (t.bank == null && t.accountTail == null) continue;
    final key = '${t.bank ?? '?'}|${t.accountTail ?? '?'}|${t.accountKind.index}';
    groups.putIfAbsent(key, () => []).add(t);
  }
  final accounts = <DerivedAccount>[];
  for (final list in groups.values) {
    // transactionsProvider is ordered newest-first already.
    Transaction? withBalance;
    for (final t in list) {
      if (t.balance != null) {
        withBalance = t;
        break;
      }
    }
    accounts.add(DerivedAccount(
      bank: list.first.bank,
      tail: list.first.accountTail,
      kind: list.first.accountKind,
      transactions: list,
      balance: withBalance?.balance,
      balanceAsOf: withBalance?.occurredAt,
    ));
  }
  accounts.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  return accounts;
});

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
      balance: Value(parsed.balance),
      occurredAt: at,
    ));
  }
  return IngestResult(parsed, txnId);
}
