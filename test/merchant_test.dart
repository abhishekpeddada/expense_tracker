import 'package:expense_tracker/parsing/merchant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MerchantName.display', () {
    test('strips reference numbers and title cases', () {
      expect(MerchantName.display('PEDDADA  VIVEK Refno 660321247164'),
          'Peddada Vivek');
    });

    test('strips rail prefixes', () {
      expect(MerchantName.display('UPI SWIGGY BANGALORE'), 'Swiggy Bangalore');
      expect(MerchantName.display('POS AMAZON PAY'), 'Amazon Pay');
    });

    test('keeps short acronyms uppercase', () {
      expect(MerchantName.display('ATM WDL'), 'ATM WDL');
    });

    test('leaves a VPA untouched', () {
      expect(MerchantName.display('merchant@ybl'), 'merchant@ybl');
    });

    test('null and empty stay null', () {
      expect(MerchantName.display(null), isNull);
      expect(MerchantName.display('  '), isNull);
      expect(MerchantName.display('Refno 123456789'), isNull);
    });
  });

  group('MerchantName.key', () {
    test('same merchant in different outlets shares a key', () {
      expect(MerchantName.key('SWIGGY BANGALORE'),
          MerchantName.key('Swiggy  Bangalore'));
    });

    test('key ignores trailing reference noise', () {
      expect(MerchantName.key('PEDDADA VIVEK Refno 660321247164'),
          'peddada vivek');
    });

    test('a VPA keys on the whole address', () {
      expect(MerchantName.key('merchant@ybl'), 'merchant@ybl');
    });
  });
}
