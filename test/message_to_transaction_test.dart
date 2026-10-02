import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:expense_tracker/data/db.dart';
import 'package:expense_tracker/data/providers.dart';
import 'package:expense_tracker/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime(2026, 10, 2, 14, 30);

  SmsMessage message(String body, {String sender = 'AD-ICICIT-S'}) =>
      SmsMessage(
        id: 1,
        sender: sender,
        body: body,
        receivedAt: at,
        isTransaction: false,
        read: true,
        outgoing: false,
      );

  group('draft from a message', () {
    test('fills in what the parser can read', () {
      final draft = draftTransactionFromMessage(message(
        'Dear Customer, Rs.2500.00 debited from A/c XX9012 on 02-10-26 '
        'at SWIGGY. Avl bal Rs.14,300.00',
      ));

      expect(draft.amount, 2500);
      expect(draft.type, TxnType.debit);
      expect(draft.accountTail, '9012');
      expect(draft.merchant, 'Swiggy');
      expect(draft.balance, 14300);
    });

    test('keeps the message so the transaction points back at it', () {
      const body = 'Rs.300 debited from A/c XX1111 at Zepto';
      final draft = draftTransactionFromMessage(message(body));

      expect(draft.rawSms, body);
      expect(draft.smsSender, 'AD-ICICIT-S');
      expect(draft.source, 'sms');
      // The time is the message's, not now: a transaction put back days
      // later still belongs to the day it happened.
      expect(draft.occurredAt, at);
    });

    test('a credit comes back as a credit', () {
      final draft = draftTransactionFromMessage(
        message('Rs.40000 credited to A/c XX9012 - SALARY'),
      );
      expect(draft.type, TxnType.credit);
      expect(draft.amount, 40000);
    });

    test('an unparseable message still gives a usable draft', () {
      final draft = draftTransactionFromMessage(
        message('Hey, are we still on for tonight?', sender: '9876543210'),
      );

      // Zero amount is the signal for "nothing found"; the form leaves the
      // field empty rather than showing it.
      expect(draft.amount, 0);
      expect(draft.rawSms, 'Hey, are we still on for tonight?');
      expect(draft.smsSender, '9876543210');
      expect(draft.occurredAt, at);
      expect(messageLooksLikeTransaction(
        message('Hey, are we still on for tonight?'),
      ), isFalse);
    });

    test('a real bank SMS is recognised as readable', () {
      expect(
        messageLooksLikeTransaction(
          message('Rs.2500.00 debited from A/c XX9012 at SWIGGY'),
        ),
        isTrue,
      );
    });

    test('an OTP is not offered as a transaction', () {
      expect(
        messageLooksLikeTransaction(
          message('123456 is your OTP for a txn of Rs 2500 at Amazon'),
        ),
        isFalse,
      );
    });
  });

  group('knowing a message already produced a transaction', () {
    late AppDb db;
    setUp(() => db = AppDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    const body = 'Rs.2500.00 debited from A/c XX9012 at SWIGGY';

    test('false before, true after', () async {
      expect(await db.hasTransactionFromSms(body), isFalse);

      await db.insertTransaction(TransactionsCompanion.insert(
        amount: 2500,
        type: TxnType.debit,
        accountKind: AccountKind.bank,
        rawSms: const Value(body),
        occurredAt: at,
      ));

      expect(await db.hasTransactionFromSms(body), isTrue);
      // A different message is unaffected.
      expect(await db.hasTransactionFromSms('Rs.10 debited'), isFalse);
    });

    test('deleting the transaction makes the message offerable again',
        () async {
      final id = await db.insertTransaction(TransactionsCompanion.insert(
        amount: 2500,
        type: TxnType.debit,
        accountKind: AccountKind.bank,
        rawSms: const Value(body),
        occurredAt: at,
      ));
      await db.deleteTransaction(id);

      // This is the whole point: an accidental delete leaves the message
      // able to recreate it.
      expect(await db.hasTransactionFromSms(body), isFalse);
    });

    test('the message can be flagged as recorded', () async {
      final id = await db.insertMessage(SmsMessagesCompanion.insert(
        sender: 'AD-ICICIT-S',
        body: body,
        receivedAt: at,
      ));
      expect((await db.watchMessages().first).single.isTransaction, isFalse);

      await db.setMessageIsTransaction(id, true);
      expect((await db.watchMessages().first).single.isTransaction, isTrue);
    });
  });
}
