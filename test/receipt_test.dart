import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:expense_tracker/data/db.dart';
import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/services/openrouter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('payment receipt', () {
    test('reads a UPI debit screenshot', () {
      final r = OpenRouterClient.parseReceipt('''
{"amount": 248.5, "direction": "debit", "merchant": "Sri Krishna Stores",
 "occurred_at": "2026-10-02T19:14:00", "bank": "SBI",
 "account_tail": "4417", "reference": "429512345678"}
''');

      expect(r.amount, 248.5);
      expect(r.type, TxnType.debit);
      expect(r.merchant, 'Sri Krishna Stores');
      expect(r.occurredAt, DateTime(2026, 10, 2, 19, 14));
      expect(r.bank, 'SBI');
      expect(r.accountTail, '4417');
      expect(r.reference, '429512345678');
    });

    test('strips the rupee symbol and thousands separators', () {
      final r = OpenRouterClient.parseReceipt(
          '{"amount": "₹1,234.00", "direction": "debit"}');
      expect(r.amount, 1234);
    });

    test('money received is a credit', () {
      final r = OpenRouterClient.parseReceipt(
          '{"amount": 500, "direction": "Credit", "merchant": "Ravi"}');
      expect(r.type, TxnType.credit);
    });

    test('anything but credit is treated as money going out', () {
      // A model that writes "paid" or omits the direction entirely still
      // has to land somewhere, and a payment is the overwhelming case.
      expect(
        OpenRouterClient.parseReceipt('{"amount": 20, "direction": "paid"}')
            .type,
        TxnType.debit,
      );
      expect(
        OpenRouterClient.parseReceipt('{"amount": 20}').type,
        TxnType.debit,
      );
    });

    test('a receipt with no date leaves the date to the caller', () {
      final r = OpenRouterClient.parseReceipt('{"amount": 60}');
      expect(r.occurredAt, isNull);
    });

    test('an unreadable date is not invented', () {
      final r = OpenRouterClient.parseReceipt(
          '{"amount": 60, "occurred_at": "2 Oct, 7:14 pm"}');
      expect(r.occurredAt, isNull);
    });

    test('ignores prose and code fences around the JSON', () {
      final r = OpenRouterClient.parseReceipt(
          'Here is the payment:\n```json\n{"amount": 99}\n```\nHope that helps.');
      expect(r.amount, 99);
    });

    test('empty strings do not become empty fields', () {
      final r = OpenRouterClient.parseReceipt(
          '{"amount": 10, "merchant": "", "bank": "  ", "reference": ""}');
      expect(r.merchant, isNull);
      expect(r.bank, isNull);
      expect(r.reference, isNull);
    });

    test('says so when the image is not a receipt', () {
      expect(
        () => OpenRouterClient.parseReceipt('{"not_a_receipt": true}'),
        throwsA(isA<OpenRouterException>().having(
          (e) => e.message,
          'message',
          contains('not look like a payment receipt'),
        )),
      );
    });

    test('refuses a receipt with no amount on it', () {
      expect(
        () => OpenRouterClient.parseReceipt('{"merchant": "Zomato"}'),
        throwsA(isA<OpenRouterException>().having(
          (e) => e.message,
          'message',
          contains('No amount'),
        )),
      );
      expect(
        () => OpenRouterClient.parseReceipt('{"amount": 0}'),
        throwsA(isA<OpenRouterException>()),
      );
    });

    test('refuses an answer that is not JSON at all', () {
      expect(
        () => OpenRouterClient.parseReceipt('I cannot read that image.'),
        throwsA(isA<OpenRouterException>()),
      );
    });
  });

  group('not recording the same payment twice', () {
    late AppDb db;
    setUp(() => db = AppDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> record(double amount, DateTime at,
            {String? note, String? merchant}) =>
        db.insertTransaction(TransactionsCompanion.insert(
          amount: amount,
          type: TxnType.debit,
          accountKind: AccountKind.bank,
          merchant: Value(merchant),
          note: Value(note),
          source: const Value('sms'),
          occurredAt: at,
        ));

    test('finds the late SMS for a receipt by its UPI reference', () async {
      await record(248.5, DateTime(2026, 6, 1),
          note: 'UPI ref 429512345678', merchant: 'Sri Krishna Stores');

      // Months apart, so only the reference can connect the two.
      final hit = await db.findReceiptDuplicate(
        amount: 248.5,
        at: DateTime(2026, 10, 2, 19, 14),
        reference: '429512345678',
      );
      expect(hit, isNotNull);
      expect(hit!.merchant, 'Sri Krishna Stores');
    });

    test('a different reference is a different payment', () async {
      await record(248.5, DateTime(2026, 6, 1), note: 'UPI ref 429512345678');
      final hit = await db.findReceiptDuplicate(
        amount: 248.5,
        at: DateTime(2026, 10, 2),
        reference: '111122223333',
      );
      expect(hit, isNull);
    });

    test('falls back to the same amount around the same time', () async {
      await record(90, DateTime(2026, 10, 2, 8, 30));
      final hit = await db.findReceiptDuplicate(
        amount: 90,
        at: DateTime(2026, 10, 2, 19, 0),
      );
      expect(hit, isNotNull);
    });

    test('the same amount weeks later is not a duplicate', () async {
      await record(90, DateTime(2026, 9, 2));
      final hit = await db.findReceiptDuplicate(
        amount: 90,
        at: DateTime(2026, 10, 2),
      );
      expect(hit, isNull);
    });

    test('a different amount on the same day is not a duplicate', () async {
      await record(90, DateTime(2026, 10, 2, 8, 30));
      final hit = await db.findReceiptDuplicate(
        amount: 95,
        at: DateTime(2026, 10, 2, 19, 0),
      );
      expect(hit, isNull);
    });

    test('nothing recorded means nothing to warn about', () async {
      final hit = await db.findReceiptDuplicate(
        amount: 90,
        at: DateTime(2026, 10, 2),
        reference: '429512345678',
      );
      expect(hit, isNull);
    });

    test('a reference with odd characters is not read as a wildcard',
        () async {
      await record(90, DateTime(2026, 6, 1), note: 'UPI ref 429512345678');
      final hit = await db.findReceiptDuplicate(
        amount: 90,
        at: DateTime(2026, 10, 2),
        reference: '%%%%%%',
      );
      expect(hit, isNull);
    });

    test('a short reference is ignored rather than matched loosely',
        () async {
      // A two-digit "reference" misread off a blurry screenshot would
      // otherwise match half the notes in the database.
      await record(90, DateTime(2026, 6, 1), note: 'bus fare 12');
      final hit = await db.findReceiptDuplicate(
        amount: 90,
        at: DateTime(2026, 10, 2),
        reference: '12',
      );
      expect(hit, isNull);
    });
  });
}
