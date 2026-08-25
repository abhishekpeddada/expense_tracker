import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/parsing/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmsParser.parse', () {
    test('HDFC debit card / account spend', () {
      final t = SmsParser.parse(
        'Rs.450.00 debited from a/c **1234 on 20-08-26 at SWIGGY BANGALORE. '
        'Avl bal Rs.12,345.10. Not you? Call 18002586161 - HDFC Bank',
        sender: 'VM-HDFCBK-S',
      );
      expect(t, isNotNull);
      expect(t!.amount, 450.00);
      expect(t.type, TxnType.debit);
      expect(t.accountKind, AccountKind.bank);
      expect(t.accountTail, '1234');
      expect(t.merchant, 'SWIGGY BANGALORE');
      expect(t.bank, 'HDFC Bank');
    });

    test('credit card spend is flagged as creditCard', () {
      final t = SmsParser.parse(
        'INR 2,499.00 spent on your ICICI Bank Credit Card XX7005 on '
        '21-Aug-26 at AMAZON PAY INDIA. Avl Limit: INR 1,02,501.00.',
        sender: 'AD-ICICIB',
      );
      expect(t, isNotNull);
      expect(t!.amount, 2499.00);
      expect(t.type, TxnType.debit);
      expect(t.accountKind, AccountKind.creditCard);
      expect(t.bank, 'ICICI Bank');
    });

    test('salary credit', () {
      final t = SmsParser.parse(
        'Rs.85,000.00 credited to a/c XX9876 on 01-08-26 from ACME TECH '
        'SALARY. Avl Bal Rs.1,02,000.00 - SBI',
        sender: 'BZ-SBIINB',
      );
      expect(t, isNotNull);
      expect(t!.amount, 85000.00);
      expect(t.type, TxnType.credit);
      expect(t.merchant, 'ACME TECH SALARY');
      expect(t.bank, 'SBI');
    });

    test('UPI debit with VPA counterparty', () {
      final t = SmsParser.parse(
        'Rs 199.00 sent to VPA merchant@ybl on 22Aug26 via UPI Ref '
        '622412345678 - Axis Bank',
        sender: 'AX-AXISBK',
      );
      expect(t, isNotNull);
      expect(t!.type, TxnType.debit);
      expect(t.merchant, 'merchant@ybl');
      expect(t.bank, 'Axis Bank');
    });

    test('refund credit', () {
      final t = SmsParser.parse(
        'Refund of Rs.599.00 credited to your Kotak a/c x4321 from FLIPKART '
        'on 23-08-26.',
        sender: 'KOTAKB',
      );
      expect(t, isNotNull);
      expect(t!.type, TxnType.credit);
      expect(t.amount, 599.00);
    });

    test('OTP mentioning an amount is rejected', () {
      final t = SmsParser.parse(
        '123456 is your OTP for a transaction of Rs.5,000.00 on your HDFC '
        'card. Do not share it with anyone.',
        sender: 'VM-HDFCBK',
      );
      expect(t, isNull);
    });

    test('bill-due reminder is rejected', () {
      final t = SmsParser.parse(
        'Your ICICI Credit Card bill of Rs.12,340.00 is due on 28-08-26. '
        'Min due Rs.620.00. Pay now to avoid charges.',
        sender: 'AD-ICICIB',
      );
      expect(t, isNull);
    });

    test('autopay pre-debit notice is rejected', () {
      final t = SmsParser.parse(
        'Rs.649.00 will be debited from your a/c XX1234 on 25-08-26 towards '
        'NETFLIX e-mandate.',
        sender: 'VM-HDFCBK',
      );
      expect(t, isNull);
    });

    test('UPI collect/payment request is rejected', () {
      final t = SmsParser.parse(
        'John Doe has requested money Rs.500.00 from you on UPI. Approve or '
        'decline in your app.',
        sender: 'JX-PAYTMB',
      );
      expect(t, isNull);
    });

    test('promo without transaction keywords is rejected', () {
      final t = SmsParser.parse(
        'Get a personal loan of Rs.5,00,000 at just 10.5% p.a. Apply now!',
        sender: 'VD-LOANS',
      );
      expect(t, isNull);
    });

    test('plain personal message is rejected', () {
      final t = SmsParser.parse('hey, dinner at 8?', sender: '+919812345678');
      expect(t, isNull);
    });
  });

  group('SmsParser.suggestCategory', () {
    ParsedTransaction debitAt(String merchant) => ParsedTransaction(
          amount: 100,
          type: TxnType.debit,
          accountKind: AccountKind.bank,
          merchant: merchant,
        );

    test('food merchants', () {
      expect(SmsParser.suggestCategory(debitAt('SWIGGY BANGALORE')),
          Categories.food);
      expect(
          SmsParser.suggestCategory(debitAt('Zomato Ltd')), Categories.food);
    });

    test('travel merchants', () {
      expect(SmsParser.suggestCategory(debitAt('UBER INDIA')),
          Categories.travel);
      expect(SmsParser.suggestCategory(debitAt('IRCTC CF')), Categories.travel);
    });

    test('shopping merchants', () {
      expect(SmsParser.suggestCategory(debitAt('AMAZON PAY INDIA')),
          Categories.shopping);
    });

    test('unknown merchant falls back to Other', () {
      expect(SmsParser.suggestCategory(debitAt('RANDOM SHOP')),
          Categories.other);
    });

    test('credits suggest salary/refund', () {
      const salary = ParsedTransaction(
        amount: 85000,
        type: TxnType.credit,
        accountKind: AccountKind.bank,
        merchant: 'ACME TECH SALARY',
      );
      expect(SmsParser.suggestCategory(salary), Categories.salary);
      const other = ParsedTransaction(
        amount: 599,
        type: TxnType.credit,
        accountKind: AccountKind.bank,
        merchant: 'FLIPKART',
      );
      expect(SmsParser.suggestCategory(other), Categories.refund);
    });
  });
}
