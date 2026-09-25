import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:expense_tracker/data/db.dart';
import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/ui/transaction_list_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sep = DateTime(2026, 9, 10);
  final aug = DateTime(2026, 8, 10);

  Transaction txn({
    int id = 1,
    double amount = 100,
    TxnType type = TxnType.debit,
    String? category,
    AccountKind kind = AccountKind.bank,
    DateTime? at,
  }) =>
      Transaction(
        id: id,
        amount: amount,
        type: type,
        accountKind: kind,
        category: category,
        source: 'sms',
        occurredAt: at ?? sep,
        createdAt: at ?? sep,
        synced: false,
      );

  group('what a dashboard figure opens', () {
    final rows = [
      txn(id: 1, amount: 500, category: Categories.food),
      txn(id: 2, amount: 300, category: null),
      txn(
          id: 3,
          amount: 900,
          category: Categories.shopping,
          kind: AccountKind.creditCard),
      txn(id: 4, amount: 40000, type: TxnType.credit,
          category: Categories.salary),
      txn(id: 5, amount: 93000, category: 'Self transfer'),
      txn(id: 6, amount: 200, category: Categories.food, at: aug),
    ];

    List<Transaction> shown(TxnFilter f) =>
        [for (final t in rows) if (f.matches(t)) t];

    test('Spent covers the month\'s debits and leaves internal out', () {
      final list = shown(
          TxnFilter(month: DateTime(2026, 9), type: TxnType.debit));
      expect(list.map((t) => t.id), [1, 2, 3]);
      expect(list.fold<double>(0, (s, t) => s + t.amount), 1700);
    });

    test('Received covers only credits', () {
      final list = shown(
          TxnFilter(month: DateTime(2026, 9), type: TxnType.credit));
      expect(list.map((t) => t.id), [4]);
    });

    test('Credit card spends covers only the card', () {
      final list = shown(TxnFilter(
        month: DateTime(2026, 9),
        type: TxnType.debit,
        creditCardOnly: true,
      ));
      expect(list.map((t) => t.id), [3]);
    });

    test('the moved-between-accounts line opens exactly those', () {
      final list =
          shown(TxnFilter(month: DateTime(2026, 9), onlyInternal: true));
      expect(list.map((t) => t.id), [5]);
    });

    test('a category slice opens that category', () {
      final list = shown(TxnFilter(
        month: DateTime(2026, 9),
        type: TxnType.debit,
        category: Categories.food,
      ));
      expect(list.map((t) => t.id), [1]);
    });

    test('the Uncategorized slice opens the ones with no category', () {
      final list = shown(TxnFilter(
        month: DateTime(2026, 9),
        type: TxnType.debit,
        uncategorizedOnly: true,
      ));
      expect(list.map((t) => t.id), [2]);
    });

    test('another month is not included', () {
      expect(shown(TxnFilter(month: DateTime(2026, 9))).map((t) => t.id),
          isNot(contains(6)));
    });

    test('all time spans every month', () {
      final list = shown(const TxnFilter(type: TxnType.debit));
      expect(list.map((t) => t.id), [1, 2, 3, 6]);
    });
  });

  group('deleting with an undo', () {
    late AppDb db;
    setUp(() => db = AppDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<int> record() => db.insertTransaction(
          TransactionsCompanion.insert(
            amount: 1250,
            type: TxnType.debit,
            accountKind: AccountKind.creditCard,
            merchant: const Value('Crocs'),
            category: const Value(Categories.shopping),
            note: const Value('birthday'),
            accountTail: const Value('9000'),
            occurredAt: sep,
          ),
        );

    test('hands back the row it removed', () async {
      final id = await record();
      final removed = await db.deleteTransactionReturning(id);

      expect(removed, isNotNull);
      expect(removed!.merchant, 'Crocs');
      expect(await db.watchTransactions().first, isEmpty);
    });

    test('undo restores it exactly, under the same id', () async {
      final id = await record();
      final removed = await db.deleteTransactionReturning(id);
      await db.restoreTransaction(removed!);

      final back = (await db.watchTransactions().first).single;
      expect(back.id, id);
      expect(back.amount, 1250);
      expect(back.merchant, 'Crocs');
      expect(back.category, Categories.shopping);
      expect(back.note, 'birthday');
      expect(back.accountTail, '9000');
      expect(back.accountKind, AccountKind.creditCard);
      expect(back.occurredAt, sep);
    });

    test('deleting something already gone returns nothing to undo',
        () async {
      final id = await record();
      await db.deleteTransactionReturning(id);
      expect(await db.deleteTransactionReturning(id), isNull);
    });

    test('undoing twice leaves one copy, not two', () async {
      final id = await record();
      final removed = await db.deleteTransactionReturning(id);
      await db.restoreTransaction(removed!);
      await db.restoreTransaction(removed);
      expect(await db.watchTransactions().first, hasLength(1));
    });
  });
}
