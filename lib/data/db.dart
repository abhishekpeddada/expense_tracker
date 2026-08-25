import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../models/models.dart';

part 'db.g.dart';

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()();
  IntColumn get type => intEnum<TxnType>()();
  IntColumn get accountKind => intEnum<AccountKind>()();
  TextColumn get accountTail => text().nullable()();
  TextColumn get merchant => text().nullable()();
  TextColumn get bank => text().nullable()();

  /// Null until the user (or auto-suggestion confirmed) categorizes it.
  TextColumn get category => text().nullable()();
  TextColumn get note => text().nullable()();

  /// Raw SMS body this transaction was parsed from, if any.
  TextColumn get rawSms => text().nullable()();
  TextColumn get smsSender => text().nullable()();

  /// Id of the native SMS queue entry this was parsed from, so category
  /// picks made on the notification can find their transaction later.
  TextColumn get smsEntryId => text().nullable()();

  /// Account balance (or credit-card available limit) after this
  /// transaction, when the SMS/statement stated one.
  RealColumn get balance => real().nullable()();

  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// False until pushed to Firestore (sync comes later).
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}

/// Local copy of SMS messages so the Messages tab can render an inbox.
/// Populated by the native SMS layer once the app holds the SMS role.
class SmsMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sender => text()();
  TextColumn get body => text()();
  DateTimeColumn get receivedAt => dateTime()();
  BoolColumn get isTransaction => boolean().withDefault(const Constant(false))();
  BoolColumn get read => boolean().withDefault(const Constant(false))();

  /// True for messages sent by the user from this app.
  BoolColumn get outgoing => boolean().withDefault(const Constant(false))();
}

@DriftDatabase(tables: [Transactions, SmsMessages])
class AppDb extends _$AppDb {
  AppDb() : super(driftDatabase(name: 'expense_tracker'));

  /// In-memory constructor for tests.
  AppDb.forTesting(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(transactions, transactions.smsEntryId);
          }
          if (from < 3) {
            await m.addColumn(smsMessages, smsMessages.outgoing);
          }
          if (from < 4) {
            await m.addColumn(transactions, transactions.balance);
          }
        },
      );

  // ---- Transactions ----

  Stream<List<Transaction>> watchTransactions() =>
      (select(transactions)..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .watch();

  Stream<List<Transaction>> watchUncategorized() => (select(transactions)
        ..where((t) => t.category.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
      .watch();

  Future<int> insertTransaction(TransactionsCompanion txn) =>
      into(transactions).insert(txn);

  Future<void> setCategory(int id, String category, {String? note}) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          category: Value(category),
          note: note == null ? const Value.absent() : Value(note),
        ),
      );

  Future<void> deleteTransaction(int id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  /// Duplicate check used by statement import: same day, amount, type, and
  /// description means the row was already imported (or came in via SMS).
  Future<bool> hasSimilarTransaction(
      DateTime day, double amount, TxnType type, String? merchant) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final q = select(transactions)
      ..where((t) =>
          t.amount.equals(amount) &
          t.type.equalsValue(type) &
          t.occurredAt.isBiggerOrEqualValue(start) &
          t.occurredAt.isSmallerThanValue(end) &
          (merchant == null
              ? t.merchant.isNull()
              : t.merchant.equals(merchant)))
      ..limit(1);
    return (await q.get()).isNotEmpty;
  }

  /// Applies a category picked on the notification to the transaction that
  /// came from that SMS entry. Only fills in uncategorized transactions —
  /// a category the user already set in-app must never be overwritten by a
  /// stale notification pick.
  Future<void> setCategoryBySmsEntry(String entryId, String category) =>
      (update(transactions)
            ..where((t) => t.smsEntryId.equals(entryId) & t.category.isNull()))
          .write(TransactionsCompanion(category: Value(category)));

  // ---- Messages ----

  Stream<List<SmsMessage>> watchMessages() =>
      (select(smsMessages)..orderBy([(m) => OrderingTerm.desc(m.receivedAt)]))
          .watch();

  /// All messages exchanged with one sender, oldest first (for thread view).
  Stream<List<SmsMessage>> watchThread(String sender) => (select(smsMessages)
        ..where((m) => m.sender.equals(sender))
        ..orderBy([(m) => OrderingTerm.asc(m.receivedAt)]))
      .watch();

  Future<int> insertMessage(SmsMessagesCompanion msg) =>
      into(smsMessages).insert(msg);

  /// Marks all incoming messages from a sender as read.
  Future<void> markThreadRead(String sender) => (update(smsMessages)
        ..where((m) =>
            m.sender.equals(sender) &
            m.read.equals(false) &
            m.outgoing.equals(false)))
      .write(const SmsMessagesCompanion(read: Value(true)));
}
