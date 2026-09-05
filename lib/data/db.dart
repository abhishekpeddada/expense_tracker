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

  /// Where this record came from: sms, manual or import. Kept for
  /// provenance when a transaction is inspected or exported.
  TextColumn get source =>
      text().withDefault(const Constant('sms'))();

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

/// Remembers that a merchant belongs to a category, so the same merchant is
/// categorized automatically next time. Learned from the user's own picks.
class CategoryRules extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Normalized merchant key (lowercased, noise stripped).
  TextColumn get merchantKey => text().unique()();
  TextColumn get category => text()();

  /// How many times the user has confirmed this pairing.
  IntColumn get hits => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// One thing eaten, logged by hand on the Food tab.
class FoodEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get meal => intEnum<Meal>()();

  /// Calories for a single serving; null when unknown, since a log entry is
  /// still useful without one.
  RealColumn get calories => real().nullable()();
  RealColumn get servings => real().withDefault(const Constant(1))();

  /// Macros for a single serving, in grams. Null when unknown.
  RealColumn get protein => real().nullable()();
  RealColumn get carbs => real().nullable()();
  RealColumn get fat => real().nullable()();

  /// What one serving means for this food ("1 cup", "2 pieces"), as stated
  /// by whatever produced the estimate.
  TextColumn get servingSize => text().nullable()();

  /// Where the nutrition numbers came from: manual, table (the built-in
  /// reference list) or ai (an OpenRouter model, whose id is kept so a
  /// figure can be traced back to what produced it).
  TextColumn get nutritionSource => text().nullable()();
  TextColumn get nutritionModel => text().nullable()();

  TextColumn get note => text().nullable()();
  DateTimeColumn get eatenAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// One turn of the assistant conversation on the Chat tab. Kept so the
/// thread and its follow-ups survive the app being closed.
class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'user' or 'assistant'.
  TextColumn get role => text()();
  TextColumn get content => text()();

  /// Model that produced an assistant turn, for provenance.
  TextColumn get model => text().nullable()();

  /// True when the turn is an error notice rather than a real answer, so it
  /// is shown differently and never sent back as conversation history.
  BoolColumn get isError => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Monthly spending cap for a category.
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get category => text().unique()();
  RealColumn get monthlyLimit => real()();
}

@DriftDatabase(tables: [
  Transactions,
  SmsMessages,
  CategoryRules,
  Budgets,
  FoodEntries,
  ChatMessages,
])
class AppDb extends _$AppDb {
  AppDb() : super(driftDatabase(name: 'expense_tracker'));

  /// In-memory constructor for tests.
  AppDb.forTesting(super.e);

  @override
  int get schemaVersion => 9;

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
          if (from < 5) {
            await m.createTable(categoryRules);
            await m.createTable(budgets);
          }
          if (from < 6) {
            await m.addColumn(transactions, transactions.source);
          }
          if (from < 7) {
            await m.createTable(foodEntries);
          }
          if (from < 8) {
            await m.addColumn(foodEntries, foodEntries.protein);
            await m.addColumn(foodEntries, foodEntries.carbs);
            await m.addColumn(foodEntries, foodEntries.fat);
            await m.addColumn(foodEntries, foodEntries.servingSize);
            await m.addColumn(foodEntries, foodEntries.nutritionSource);
            await m.addColumn(foodEntries, foodEntries.nutritionModel);
          }
          if (from < 9) {
            await m.createTable(chatMessages);
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

  /// Duplicate check used when restoring a backup.
  Future<bool> hasMessage(String sender, String body, DateTime at) async {
    final q = select(smsMessages)
      ..where((m) =>
          m.sender.equals(sender) &
          m.body.equals(body) &
          m.receivedAt.equals(at))
      ..limit(1);
    return (await q.get()).isNotEmpty;
  }

  Future<void> deleteMessage(int id) =>
      (delete(smsMessages)..where((m) => m.id.equals(id))).go();

  /// Removes an entire conversation.
  Future<void> deleteThread(String sender) =>
      (delete(smsMessages)..where((m) => m.sender.equals(sender))).go();

  /// Marks the newest incoming message of a thread unread again.
  Future<void> markThreadUnread(String sender) async {
    final newest = await (select(smsMessages)
          ..where((m) => m.sender.equals(sender) & m.outgoing.equals(false))
          ..orderBy([(m) => OrderingTerm.desc(m.receivedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (newest == null) return;
    await (update(smsMessages)..where((m) => m.id.equals(newest.id)))
        .write(const SmsMessagesCompanion(read: Value(false)));
  }

  // ---- Category rules (learned auto-categorization) ----

  Future<String?> categoryForMerchant(String merchantKey) async {
    final row = await (select(categoryRules)
          ..where((r) => r.merchantKey.equals(merchantKey))
          ..limit(1))
        .getSingleOrNull();
    return row?.category;
  }

  /// Records (or reinforces) that a merchant maps to a category.
  Future<void> rememberCategory(String merchantKey, String category) async {
    final existing = await (select(categoryRules)
          ..where((r) => r.merchantKey.equals(merchantKey))
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) {
      await into(categoryRules).insert(CategoryRulesCompanion.insert(
        merchantKey: merchantKey,
        category: category,
      ));
    } else {
      await (update(categoryRules)..where((r) => r.id.equals(existing.id)))
          .write(CategoryRulesCompanion(
        category: Value(category),
        // A changed category restarts the count; the newest pick wins.
        hits: Value(existing.category == category ? existing.hits + 1 : 1),
        updatedAt: Value(DateTime.now()),
      ));
    }
  }

  Stream<List<CategoryRule>> watchCategoryRules() => (select(categoryRules)
        ..orderBy([(r) => OrderingTerm.desc(r.hits)]))
      .watch();

  Future<void> deleteCategoryRule(int id) =>
      (delete(categoryRules)..where((r) => r.id.equals(id))).go();

  // ---- Budgets ----

  Stream<List<Budget>> watchBudgets() => select(budgets).watch();
  Future<List<Budget>> allBudgets() => select(budgets).get();

  Future<void> setBudget(String category, double limit) async {
    final existing = await (select(budgets)
          ..where((b) => b.category.equals(category))
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) {
      await into(budgets).insert(
          BudgetsCompanion.insert(category: category, monthlyLimit: limit));
    } else {
      await (update(budgets)..where((b) => b.id.equals(existing.id)))
          .write(BudgetsCompanion(monthlyLimit: Value(limit)));
    }
  }

  Future<void> deleteBudget(String category) =>
      (delete(budgets)..where((b) => b.category.equals(category))).go();

  // ---- Transaction editing ----

  Future<void> updateTransaction(
    int id, {
    required double amount,
    required TxnType type,
    required AccountKind accountKind,
    String? merchant,
    String? bank,
    String? accountTail,
    String? category,
    String? note,
    required DateTime occurredAt,
  }) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          amount: Value(amount),
          type: Value(type),
          accountKind: Value(accountKind),
          merchant: Value(merchant),
          bank: Value(bank),
          accountTail: Value(accountTail),
          category: Value(category),
          note: Value(note),
          occurredAt: Value(occurredAt),
        ),
      );

  // ---- Food log ----

  Stream<List<FoodEntry>> watchFoodEntries() => (select(foodEntries)
        ..orderBy([(f) => OrderingTerm.desc(f.eatenAt)]))
      .watch();

  /// Everything eaten on one calendar day, earliest first.
  Stream<List<FoodEntry>> watchFoodForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(foodEntries)
          ..where((f) =>
              f.eatenAt.isBiggerOrEqualValue(start) &
              f.eatenAt.isSmallerThanValue(end))
          ..orderBy([(f) => OrderingTerm.asc(f.eatenAt)]))
        .watch();
  }

  Future<int> insertFoodEntry(FoodEntriesCompanion entry) =>
      into(foodEntries).insert(entry);

  Future<void> updateFoodEntry(
    int id, {
    required String name,
    required Meal meal,
    double? calories,
    required double servings,
    double? protein,
    double? carbs,
    double? fat,
    String? servingSize,
    String? nutritionSource,
    String? nutritionModel,
    String? note,
    required DateTime eatenAt,
  }) =>
      (update(foodEntries)..where((f) => f.id.equals(id))).write(
        FoodEntriesCompanion(
          name: Value(name),
          meal: Value(meal),
          calories: Value(calories),
          servings: Value(servings),
          protein: Value(protein),
          carbs: Value(carbs),
          fat: Value(fat),
          servingSize: Value(servingSize),
          nutritionSource: Value(nutritionSource),
          nutritionModel: Value(nutritionModel),
          note: Value(note),
          eatenAt: Value(eatenAt),
        ),
      );

  Future<void> deleteFoodEntry(int id) =>
      (delete(foodEntries)..where((f) => f.id.equals(id))).go();

  // ---- Chat ----

  /// The whole conversation, oldest first.
  Stream<List<ChatMessage>> watchChat() => (select(chatMessages)
        ..orderBy([(c) => OrderingTerm.asc(c.createdAt), (c) => OrderingTerm.asc(c.id)]))
      .watch();

  Future<List<ChatMessage>> chatHistory() => (select(chatMessages)
        ..orderBy([(c) => OrderingTerm.asc(c.createdAt), (c) => OrderingTerm.asc(c.id)]))
      .get();

  Future<int> insertChatMessage(ChatMessagesCompanion message) =>
      into(chatMessages).insert(message);

  Future<void> deleteChatMessage(int id) =>
      (delete(chatMessages)..where((c) => c.id.equals(id))).go();

  Future<void> clearChat() => delete(chatMessages).go();

  /// True when the same food is already logged at the same moment, so a
  /// backup restored twice does not duplicate the log.
  Future<bool> hasFoodEntry(String name, DateTime eatenAt) async {
    final q = select(foodEntries)
      ..where((f) => f.name.equals(name) & f.eatenAt.equals(eatenAt))
      ..limit(1);
    return (await q.get()).isNotEmpty;
  }

  /// Marks all incoming messages from a sender as read.
  Future<void> markThreadRead(String sender) => (update(smsMessages)
        ..where((m) =>
            m.sender.equals(sender) &
            m.read.equals(false) &
            m.outgoing.equals(false)))
      .write(const SmsMessagesCompanion(read: Value(true)));
}
