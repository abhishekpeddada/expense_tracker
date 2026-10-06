import 'package:expense_tracker/data/db.dart';
import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/services/card_cycle.dart';
import 'package:expense_tracker/services/chat_context.dart';
import 'package:expense_tracker/ui/transaction_list_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cycle = CardCycle(closingDay: 25, dueDay: 15);

  Transaction txn({
    required int id,
    required double amount,
    required DateTime at,
    AccountKind kind = AccountKind.creditCard,
    TxnType type = TxnType.debit,
    String? category,
  }) =>
      Transaction(
        id: id,
        amount: amount,
        type: type,
        accountKind: kind,
        category: category,
        merchant: 'Shop $id',
        source: 'sms',
        occurredAt: at,
        createdAt: at,
        synced: false,
      );

  group('the drill-down window', () {
    // The period closing 25 Oct: 26 Sep through 25 Oct.
    final oct = cycle.closingIn(DateTime(2026, 10));
    final filter = TxnFilter(
      from: oct.start,
      toExclusive: oct.endExclusive,
      periodLabel: oct.label,
      type: TxnType.debit,
      creditCardOnly: true,
    );

    test('takes in a spend on the first day of the period', () {
      expect(filter.matches(txn(id: 1, amount: 10, at: DateTime(2026, 9, 26))),
          isTrue);
    });

    test('leaves out the day before the period opened', () {
      expect(
          filter.matches(
              txn(id: 1, amount: 10, at: DateTime(2026, 9, 25, 22))),
          isFalse);
    });

    test('takes in a late spend on the closing day', () {
      expect(
          filter.matches(
              txn(id: 1, amount: 10, at: DateTime(2026, 10, 25, 23, 59))),
          isTrue);
    });

    test('leaves out the first minute after closing', () {
      expect(filter.matches(txn(id: 1, amount: 10, at: DateTime(2026, 10, 26))),
          isFalse);
    });

    test('still only counts the card', () {
      expect(
        filter.matches(txn(
            id: 1,
            amount: 10,
            at: DateTime(2026, 10, 1),
            kind: AccountKind.bank)),
        isFalse,
      );
    });

    test('still leaves out the bill payment itself', () {
      // Paying the bill is moving money between the person's own accounts,
      // so counting it on top of the spending would double it.
      expect(
        filter.matches(txn(
          id: 1,
          amount: 5000,
          at: DateTime(2026, 10, 1),
          category: Categories.creditCardBill,
        )),
        isFalse,
      );
    });

    test('a window beats a month when both are given', () {
      // The dashboard passes both so the heading can fall back, and the
      // window has to be the one that decides.
      final both = TxnFilter(
        month: DateTime(2026, 10),
        from: oct.start,
        toExclusive: oct.endExclusive,
      );
      expect(both.matches(txn(id: 1, amount: 10, at: DateTime(2026, 9, 28))),
          isTrue);
      expect(both.matches(txn(id: 1, amount: 10, at: DateTime(2026, 10, 30))),
          isFalse);
    });
  });

  group('what the assistant is told', () {
    // A spend in each period, placed so a calendar month would split them
    // the wrong way.
    final rows = [
      txn(id: 1, amount: 900, at: DateTime(2026, 9, 28)), // open period
      txn(id: 2, amount: 100, at: DateTime(2026, 10, 2)), // open period
      txn(id: 3, amount: 700, at: DateTime(2026, 9, 20)), // previous period
      txn(
        id: 4,
        amount: 50,
        at: DateTime(2026, 10, 3),
        kind: AccountKind.bank,
      ),
    ];

    String briefing() => ChatContext.build(
          transactions: rows,
          budgets: const [],
          food: const [],
          accounts: const [],
          cardCycle: cycle,
          now: DateTime(2026, 10, 6),
        );

    test('names the open period and what is on it', () {
      final text = briefing();
      expect(text, contains('CREDIT CARD STATEMENT PERIODS'));
      // 900 + 100, and not the 700 from the period before, nor the 50
      // that was not on the card.
      expect(text, contains('26 Sep 2026 to 25 Oct 2026'));
      expect(text, contains('Rs 1,000'));
    });

    test('names the previous period and when its bill is due', () {
      final text = briefing();
      expect(text, contains('26 Aug 2026 to 25 Sep 2026'));
      expect(text, contains('Rs 700'));
      expect(text, contains('15 Oct 2026'));
    });

    test('says outright that a period is not a calendar month', () {
      expect(briefing(), contains('not the calendar month'));
    });

    test('is left out entirely when there is no card spending', () {
      final text = ChatContext.build(
        transactions: [
          txn(
            id: 1,
            amount: 50,
            at: DateTime(2026, 10, 3),
            kind: AccountKind.bank,
          ),
        ],
        budgets: const [],
        food: const [],
        accounts: const [],
        cardCycle: cycle,
        now: DateTime(2026, 10, 6),
      );
      expect(text, isNot(contains('CREDIT CARD STATEMENT PERIODS')));
    });
  });
}
