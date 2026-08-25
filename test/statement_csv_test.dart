import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/parsing/sms_parser.dart';
import 'package:expense_tracker/parsing/statement_csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmsParser balance extraction', () {
    test('bank balance', () {
      final t = SmsParser.parse(
        'Rs.450.00 debited from a/c **1234 on 20-08-26 at SWIGGY. '
        'Avl bal Rs.12,345.10 - HDFC Bank',
        sender: 'VM-HDFCBK',
      );
      expect(t!.balance, 12345.10);
    });

    test('credit card available limit', () {
      final t = SmsParser.parse(
        'INR 2,499.00 spent on your ICICI Credit Card XX7005 at AMAZON. '
        'Avl Limit: INR 1,02,501.00.',
        sender: 'AD-ICICIB',
      );
      expect(t!.balance, 102501.00);
      expect(t.accountKind, AccountKind.creditCard);
    });

    test('no balance stated', () {
      final t = SmsParser.parse(
        'Rs 199.00 sent to VPA merchant@ybl via UPI Ref 1234 - Axis Bank',
        sender: 'AX-AXISBK',
      );
      expect(t!.balance, isNull);
    });
  });

  group('StatementCsvParser', () {
    test('HDFC-style: separate withdrawal/deposit columns with preamble', () {
      const csv = '''
HDFC BANK Ltd.
Statement of account,,,,,
,,,,,
Date,Narration,Chq/Ref No,Value Date,Withdrawal Amt,Deposit Amt,Closing Balance
01/08/26,UPI-SWIGGY-swiggy@icici,REF123,01/08/26,450.00,,"54,321.00"
03/08/26,SALARY ACME TECH,NEFT456,03/08/26,,"85,000.00","1,39,321.00"
05/08/26,ATM WDL MG ROAD,ATM789,05/08/26,"2,000.00",,"1,37,321.00"
''';
      final rows = StatementCsvParser.parse(csv);
      expect(rows.length, 3);
      expect(rows[0].type, TxnType.debit);
      expect(rows[0].amount, 450.00);
      expect(rows[0].date, DateTime(2026, 8, 1));
      expect(rows[0].description, contains('SWIGGY'));
      expect(rows[0].balance, 54321.00);
      expect(rows[1].type, TxnType.credit);
      expect(rows[1].amount, 85000.00);
      expect(rows[2].amount, 2000.00);
    });

    test('SBI-style: dd MMM yyyy dates, Debit/Credit columns', () {
      const csv = '''
Txn Date,Value Date,Description,Ref No./Cheque No.,Debit,Credit,Balance
01 Aug 2026,01 Aug 2026,TO TRANSFER-UPI/DR/xyz,REF1,199.00,,10000.00
02 Aug 2026,02 Aug 2026,BY TRANSFER-NEFT,REF2,,5000.00,15000.00
''';
      final rows = StatementCsvParser.parse(csv);
      expect(rows.length, 2);
      expect(rows[0].type, TxnType.debit);
      expect(rows[0].date, DateTime(2026, 8, 1));
      expect(rows[1].type, TxnType.credit);
      expect(rows[1].balance, 15000.00);
    });

    test('single amount column with Dr/Cr indicator', () {
      const csv = '''
Date,Particulars,Amount,Dr/Cr,Balance
05-08-2026,POS AMAZON,1250.50,Dr,8749.50
06-08-2026,REFUND FLIPKART,599.00,Cr,9348.50
''';
      final rows = StatementCsvParser.parse(csv);
      expect(rows.length, 2);
      expect(rows[0].type, TxnType.debit);
      expect(rows[0].amount, 1250.50);
      expect(rows[1].type, TxnType.credit);
    });

    test('signed amount column without indicator', () {
      const csv = '''
Date,Description,Amount,Balance
2026-08-10,UPI PAYMENT,-350.00,5000.00
2026-08-11,CASHBACK,25.00,5025.00
''';
      final rows = StatementCsvParser.parse(csv);
      expect(rows.length, 2);
      expect(rows[0].type, TxnType.debit);
      expect(rows[0].amount, 350.00);
      expect(rows[1].type, TxnType.credit);
    });

    test('garbage file yields nothing', () {
      expect(StatementCsvParser.parse('hello\nworld,foo\n'), isEmpty);
      expect(StatementCsvParser.parse(''), isEmpty);
    });
  });
}
