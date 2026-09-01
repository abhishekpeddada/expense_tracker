import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:expense_tracker/data/db.dart';
import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/services/insights.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a Transaction row without touching a database.
Transaction txn({
  required double amount,
  required DateTime at,
  String? merchant,
  String? category,
  TxnType type = TxnType.debit,
  int id = 0,
}) =>
    Transaction(
      id: id,
      amount: amount,
      type: type,
      accountKind: AccountKind.bank,
      merchant: merchant,
      category: category,
      occurredAt: at,
      createdAt: at,
      synced: false,
      source: 'sms',
    );

void main() {
  final thisMonth = DateTime(2026, 8, 15);
  final lastMonth = DateTime(2026, 7, 15);

  group('Insights.forMonth', () {
    test('reports an increase against last month', () {
      final all = [
        txn(amount: 1000, at: lastMonth, category: Categories.food),
        txn(amount: 2000, at: thisMonth, category: Categories.food),
      ];
      final out = Insights.forMonth(all, thisMonth);
      expect(out.map((i) => i.text).join(' '), contains('100% more'));
    });

    test('reports a decrease as good news', () {
      final all = [
        txn(amount: 2000, at: lastMonth, category: Categories.food),
        txn(amount: 1000, at: thisMonth, category: Categories.food),
      ];
      final out = Insights.forMonth(all, thisMonth);
      expect(out.first.text, contains('50% less'));
      expect(out.first.tone, InsightTone.good);
    });

    test('names the biggest category', () {
      final all = [
        txn(amount: 300, at: thisMonth, category: Categories.food),
        txn(amount: 700, at: thisMonth, category: Categories.shopping),
      ];
      final text = Insights.forMonth(all, thisMonth).map((i) => i.text).join();
      expect(text, contains('Shopping'));
      expect(text, contains('70%'));
    });

    test('counts uncategorized transactions', () {
      final all = [txn(amount: 100, at: thisMonth)];
      final text = Insights.forMonth(all, thisMonth).map((i) => i.text).join();
      expect(text, contains('1 transaction still need'));
    });

    test('credit card bill payments are excluded from spend', () {
      final all = [
        txn(amount: 5000, at: thisMonth, category: Categories.creditCardBill),
        txn(amount: 100, at: thisMonth, category: Categories.food),
      ];
      final text = Insights.forMonth(all, thisMonth).map((i) => i.text).join();
      expect(text, contains('Food & Dining'));
      expect(text, isNot(contains('5000')));
    });

    test('empty month says so', () {
      expect(Insights.forMonth([], thisMonth).first.text,
          'No transactions this month.');
    });
  });

  group('Insights.monthlyTotals', () {
    test('returns one entry per month, oldest first', () {
      final totals = Insights.monthlyTotals([], months: 6);
      expect(totals.length, 6);
      expect(totals.first.key.isBefore(totals.last.key), isTrue);
    });
  });

  group('Insights.recurring', () {
    test('detects a monthly subscription', () {
      final all = [
        for (var i = 0; i < 4; i++)
          txn(amount: 649, at: DateTime(2026, 5 + i, 10), merchant: 'Netflix'),
      ];
      final found = Insights.recurring(all);
      expect(found, hasLength(1));
      expect(found.first.merchant, 'Netflix');
      expect(found.first.typicalAmount, 649);
      expect(found.first.cadence, 'monthly');
    });

    test('ignores irregular one-off spending at the same merchant', () {
      final all = [
        txn(amount: 120, at: DateTime(2026, 8, 1), merchant: 'Swiggy'),
        txn(amount: 890, at: DateTime(2026, 8, 3), merchant: 'Swiggy'),
        txn(amount: 240, at: DateTime(2026, 8, 20), merchant: 'Swiggy'),
      ];
      expect(Insights.recurring(all), isEmpty);
    });

    test('needs at least three charges', () {
      final all = [
        txn(amount: 649, at: DateTime(2026, 6, 10), merchant: 'Netflix'),
        txn(amount: 649, at: DateTime(2026, 7, 10), merchant: 'Netflix'),
      ];
      expect(Insights.recurring(all), isEmpty);
    });
  });

  group('database', () {
    late AppDb db;
    setUp(() => db = AppDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('remembers a merchant category and reuses it', () async {
      await db.rememberCategory('swiggy', Categories.food);
      expect(await db.categoryForMerchant('swiggy'), Categories.food);
    });

    test('re-teaching a merchant replaces the category', () async {
      await db.rememberCategory('swiggy', Categories.food);
      await db.rememberCategory('swiggy', Categories.groceries);
      expect(await db.categoryForMerchant('swiggy'), Categories.groceries);
    });

    test('budgets can be set, updated and removed', () async {
      await db.setBudget(Categories.food, 5000);
      expect((await db.allBudgets()).single.monthlyLimit, 5000);
      await db.setBudget(Categories.food, 7000);
      expect((await db.allBudgets()).single.monthlyLimit, 7000);
      await db.deleteBudget(Categories.food);
      expect(await db.allBudgets(), isEmpty);
    });

    test('deleting a thread removes only that conversation', () async {
      await db.insertMessage(SmsMessagesCompanion.insert(
          sender: 'A', body: 'x', receivedAt: DateTime(2026, 8, 1)));
      await db.insertMessage(SmsMessagesCompanion.insert(
          sender: 'B', body: 'y', receivedAt: DateTime(2026, 8, 2)));
      await db.deleteThread('A');
      final left = await db.watchMessages().first;
      expect(left, hasLength(1));
      expect(left.single.sender, 'B');
    });

    test('marking a thread unread flips the newest incoming message',
        () async {
      await db.insertMessage(SmsMessagesCompanion.insert(
        sender: 'A',
        body: 'x',
        receivedAt: DateTime(2026, 8, 1),
        read: const Value(true),
      ));
      await db.markThreadUnread('A');
      final msgs = await db.watchMessages().first;
      expect(msgs.single.read, isFalse);
    });
  });
}
