import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:expense_tracker/data/db.dart';
import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/services/insights.dart';
import 'package:expense_tracker/services/self_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final noon = DateTime(2026, 9, 15, 12);

  Transaction txn({
    required int id,
    required double amount,
    required TxnType type,
    String? bank,
    String? tail,
    String? category,
    AccountKind kind = AccountKind.bank,
    DateTime? at,
  }) =>
      Transaction(
        id: id,
        amount: amount,
        type: type,
        accountKind: kind,
        accountTail: tail,
        bank: bank,
        category: category,
        source: 'sms',
        occurredAt: at ?? noon,
        createdAt: at ?? noon,
        synced: false,
      );

  group('what counts as spending', () {
    test('a self transfer is neither spent nor received', () {
      final txns = [
        txn(id: 1, amount: 5000, type: TxnType.debit, bank: 'HDFC',
            category: Categories.selfTransfer),
        txn(id: 2, amount: 5000, type: TxnType.credit, bank: 'ICICI',
            category: Categories.selfTransfer),
        txn(id: 3, amount: 300, type: TxnType.debit, bank: 'HDFC',
            category: Categories.food),
        txn(id: 4, amount: 40000, type: TxnType.credit, bank: 'HDFC',
            category: Categories.salary),
      ];

      expect(Insights.byCategory(txns)[Categories.selfTransfer], isNull);
      expect(Insights.received(txns), 40000);
      expect(Insights.internal(txns), 10000);
      // Spend is reachable through the monthly total for this month.
      final month = Insights.monthlyTotals(txns, months: 1).single.value;
      expect(month, 300);
    });

    test('a transfer to somebody else is still spending', () {
      final txns = [
        txn(id: 1, amount: 500, type: TxnType.debit, bank: 'HDFC',
            category: Categories.transfer),
      ];
      expect(Insights.byCategory(txns)[Categories.transfer], 500);
      expect(Categories.isInternal(Categories.transfer), isFalse);
    });

    test('credit card bill payments are internal too', () {
      expect(Categories.isInternal(Categories.creditCardBill), isTrue);
      expect(Categories.isInternal(Categories.selfTransfer), isTrue);
      expect(Categories.isInternal(null), isFalse);
      expect(Categories.isInternal(Categories.food), isFalse);
    });

    test('a big self transfer is not reported as the largest spend', () {
      final insights = Insights.forMonth([
        txn(id: 1, amount: 90000, type: TxnType.debit, bank: 'HDFC',
            category: Categories.selfTransfer),
        txn(id: 2, amount: 90000, type: TxnType.credit, bank: 'ICICI',
            category: Categories.selfTransfer),
        txn(id: 3, amount: 1200, type: TxnType.debit, bank: 'HDFC',
            category: Categories.shopping),
      ], noon);
      expect(insights.map((i) => i.text).join(' '), isNot(contains('90,000')));
    });

    test('Self Transfer is offered as a category', () {
      expect(Categories.all, contains(Categories.selfTransfer));
    });
  });

  group('detecting a self transfer', () {
    test('matches an identical amount landing on another account', () {
      final matches = SelfTransfers.detect([
        txn(id: 1, amount: 5000, type: TxnType.debit, bank: 'HDFC',
            tail: '1111', at: noon),
        txn(
            id: 2,
            amount: 5000,
            type: TxnType.credit,
            bank: 'ICICI',
            tail: '2222',
            at: noon.add(const Duration(minutes: 2))),
      ]);
      expect(matches, hasLength(1));
      expect(matches.single.debit.id, 1);
      expect(matches.single.credit.id, 2);
      expect(matches.single.gap, const Duration(minutes: 2));
    });

    test('a refund back to the same account is not a transfer', () {
      final matches = SelfTransfers.detect([
        txn(id: 1, amount: 700, type: TxnType.debit, bank: 'HDFC',
            tail: '1111', at: noon),
        txn(
            id: 2,
            amount: 700,
            type: TxnType.credit,
            bank: 'HDFC',
            tail: '1111',
            at: noon.add(const Duration(hours: 1))),
      ]);
      expect(matches, isEmpty);
    });

    test('a different amount is not a match', () {
      final matches = SelfTransfers.detect([
        txn(id: 1, amount: 5000, type: TxnType.debit, bank: 'HDFC',
            tail: '1111', at: noon),
        txn(id: 2, amount: 4990, type: TxnType.credit, bank: 'ICICI',
            tail: '2222', at: noon.add(const Duration(minutes: 5))),
      ]);
      expect(matches, isEmpty);
    });

    test('too far apart in time is not a match', () {
      final matches = SelfTransfers.detect([
        txn(id: 1, amount: 5000, type: TxnType.debit, bank: 'HDFC',
            tail: '1111', at: noon),
        txn(
            id: 2,
            amount: 5000,
            type: TxnType.credit,
            bank: 'ICICI',
            tail: '2222',
            at: noon.add(const Duration(hours: 7))),
      ]);
      expect(matches, isEmpty);
    });

    test('transactions with no account detail are left alone', () {
      final matches = SelfTransfers.detect([
        txn(id: 1, amount: 5000, type: TxnType.debit, at: noon),
        txn(id: 2, amount: 5000, type: TxnType.credit, at: noon),
      ]);
      expect(matches, isEmpty);
    });

    test('the nearest credit wins and nothing is matched twice', () {
      final matches = SelfTransfers.detect([
        txn(id: 1, amount: 100, type: TxnType.debit, bank: 'HDFC',
            tail: '1111', at: noon),
        txn(id: 2, amount: 100, type: TxnType.debit, bank: 'HDFC',
            tail: '1111', at: noon.add(const Duration(hours: 3))),
        txn(
            id: 3,
            amount: 100,
            type: TxnType.credit,
            bank: 'ICICI',
            tail: '2222',
            at: noon.add(const Duration(minutes: 1))),
        txn(
            id: 4,
            amount: 100,
            type: TxnType.credit,
            bank: 'ICICI',
            tail: '2222',
            at: noon.add(const Duration(hours: 3, minutes: 1))),
      ]);
      expect(matches, hasLength(2));
      expect(matches.map((m) => m.debit.id), [1, 2]);
      expect(matches.map((m) => m.credit.id), [3, 4]);
    });

    test('a card and a bank account are different accounts', () {
      final matches = SelfTransfers.detect([
        txn(id: 1, amount: 2000, type: TxnType.debit, bank: 'HDFC',
            tail: '1111', at: noon),
        txn(
            id: 2,
            amount: 2000,
            type: TxnType.credit,
            bank: 'HDFC',
            tail: '1111',
            kind: AccountKind.creditCard,
            at: noon.add(const Duration(minutes: 3))),
      ]);
      expect(matches, hasLength(1));
    });
  });

  group('pairs that already carry a category', () {
    SelfTransferMatch pair(String? debitCategory, String? creditCategory) =>
        SelfTransfers.detect([
          txn(id: 1, amount: 900, type: TxnType.debit, bank: 'HDFC',
              tail: '1111', category: debitCategory, at: noon),
          txn(
              id: 2,
              amount: 900,
              type: TxnType.credit,
              bank: 'ICICI',
              tail: '2222',
              category: creditCategory,
              at: noon.add(const Duration(minutes: 4))),
        ]).single;

    test('Other says nothing, so it is relabelled without asking', () {
      expect(pair(Categories.other, Categories.other).canApplySilently,
          isTrue);
      expect(pair(null, Categories.other).canApplySilently, isTrue);
    });

    test('a real category is never overwritten silently', () {
      expect(pair(Categories.rent, null).canApplySilently, isFalse);
      expect(pair(null, Categories.salary).canApplySilently, isFalse);
    });

    test('Transfer and Refund are offered, ticked, for review', () {
      expect(pair(Categories.transfer, Categories.refund).isLikely, isTrue);
      expect(pair(Categories.transfer, Categories.refund).canApplySilently,
          isFalse);
    });

    test('a deliberate category is shown unticked', () {
      expect(pair(Categories.rent, Categories.refund).isLikely, isFalse);
    });

    test('a pair already labelled is settled and drops off the list', () {
      final settled =
          pair(Categories.selfTransfer, Categories.selfTransfer);
      expect(settled.isSettled, isTrue);
      expect(
        SelfTransfers.suggestions([
          txn(id: 1, amount: 900, type: TxnType.debit, bank: 'HDFC',
              tail: '1111', category: Categories.selfTransfer, at: noon),
          txn(
              id: 2,
              amount: 900,
              type: TxnType.credit,
              bank: 'ICICI',
              tail: '2222',
              category: Categories.selfTransfer,
              at: noon.add(const Duration(minutes: 4))),
        ]),
        isEmpty,
      );
    });

    test('a half-labelled pair still needs review', () {
      expect(pair(Categories.selfTransfer, Categories.refund).isSettled,
          isFalse);
    });
  });

  group('labelling detected pairs', () {
    late AppDb db;
    setUp(() => db = AppDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<int> record({
      required double amount,
      required TxnType type,
      required String bank,
      required String tail,
      String? category,
      required DateTime at,
    }) =>
        db.insertTransaction(TransactionsCompanion.insert(
          amount: amount,
          type: type,
          accountKind: AccountKind.bank,
          accountTail: Value(tail),
          bank: Value(bank),
          category: Value(category),
          occurredAt: at,
        ));

    test('labels both sides of an uncategorized pair', () async {
      await record(
          amount: 5000,
          type: TxnType.debit,
          bank: 'HDFC',
          tail: '1111',
          at: noon);
      await record(
          amount: 5000,
          type: TxnType.credit,
          bank: 'ICICI',
          tail: '2222',
          at: noon.add(const Duration(minutes: 2)));

      expect(await SelfTransfers.apply(db), 1);

      final all = await db.watchTransactions().first;
      expect(all.every((t) => t.category == Categories.selfTransfer), isTrue);
    });

    test('relabels a pair filed under Other without asking', () async {
      await record(
          amount: 5000,
          type: TxnType.debit,
          bank: 'HDFC',
          tail: '1111',
          category: Categories.other,
          at: noon);
      await record(
          amount: 5000,
          type: TxnType.credit,
          bank: 'ICICI',
          tail: '2222',
          category: Categories.other,
          at: noon.add(const Duration(minutes: 2)));

      expect(await SelfTransfers.apply(db), 1);
      final all = await db.watchTransactions().first;
      expect(all.every((t) => t.category == Categories.selfTransfer), isTrue);
    });

    test('a categorized pair is offered for review instead', () async {
      await record(
          amount: 5000,
          type: TxnType.debit,
          bank: 'HDFC',
          tail: '1111',
          category: Categories.transfer,
          at: noon);
      await record(
          amount: 5000,
          type: TxnType.credit,
          bank: 'ICICI',
          tail: '2222',
          category: Categories.refund,
          at: noon.add(const Duration(minutes: 2)));

      expect(await SelfTransfers.apply(db), 0);

      final all = await db.watchTransactions().first;
      final suggestions = SelfTransfers.suggestions(all);
      expect(suggestions, hasLength(1));
      expect(suggestions.single.isLikely, isTrue);

      // Confirming from the review screen overrides both categories.
      await SelfTransfers.label(db, suggestions.single);
      final after = await db.watchTransactions().first;
      expect(after.every((t) => t.category == Categories.selfTransfer),
          isTrue);
      expect(SelfTransfers.suggestions(after), isEmpty);
    });

    test('never overwrites a category already set', () async {
      await record(
          amount: 5000,
          type: TxnType.debit,
          bank: 'HDFC',
          tail: '1111',
          category: Categories.rent,
          at: noon);
      await record(
          amount: 5000,
          type: TxnType.credit,
          bank: 'ICICI',
          tail: '2222',
          at: noon.add(const Duration(minutes: 2)));

      expect(await SelfTransfers.apply(db), 0);

      final all = await db.watchTransactions().first;
      expect(all.map((t) => t.category), containsAll([Categories.rent, null]));
    });

    test('running twice changes nothing the second time', () async {
      await record(
          amount: 800,
          type: TxnType.debit,
          bank: 'HDFC',
          tail: '1111',
          at: noon);
      await record(
          amount: 800,
          type: TxnType.credit,
          bank: 'SBI',
          tail: '3333',
          at: noon.add(const Duration(minutes: 1)));

      expect(await SelfTransfers.apply(db), 1);
      expect(await SelfTransfers.apply(db), 0);
    });
  });
}
