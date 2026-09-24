import 'package:expense_tracker/parsing/message_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<MessagePart> links(String body) =>
      MessageLinks.parse(body).where((p) => p.isLink).toList();

  String? first(String body, LinkKind kind) {
    for (final p in MessageLinks.parse(body)) {
      if (p.kind == kind) return p.value;
    }
    return null;
  }

  group('links', () {
    test('finds a full URL', () {
      expect(first('Track at https://icicibank.com/track now', LinkKind.url),
          'https://icicibank.com/track');
    });

    test('gives a scheme to a www link', () {
      expect(first('Visit www.hdfcbank.com for details', LinkKind.url),
          'https://www.hdfcbank.com');
    });

    test('finds a short link with no scheme', () {
      expect(first('Details: hdfcbk.io/a/x9Kq2', LinkKind.url),
          'https://hdfcbk.io/a/x9Kq2');
    });

    test('a full stop ending the sentence is not part of the link', () {
      final part = links('See https://sbi.co.in/offers.')
          .firstWhere((p) => p.kind == LinkKind.url);
      expect(part.text, 'https://sbi.co.in/offers');
    });

    test('a bare domain with no path is left alone', () {
      // Otherwise "Rs.500" and "a/c" shapes start looking like links.
      expect(links('Paid Rs.500 to Acme Ltd.'), isEmpty);
    });

    test('an account number is not a link', () {
      expect(
          links('A/c XX9012 debited by 250.00'), isEmpty);
    });
  });

  group('phone numbers', () {
    test('finds a ten digit mobile', () {
      expect(first('Call 9876543210 for help', LinkKind.phone),
          'tel:9876543210');
    });

    test('handles a country code and spacing', () {
      expect(first('Reach us on +91 98765 43210', LinkKind.phone),
          'tel:+919876543210');
      expect(first('Call 98765-43210', LinkKind.phone), 'tel:9876543210');
    });

    test('finds a toll free number', () {
      expect(first('Dial 1800 266 0101 to block', LinkKind.phone),
          'tel:18002660101');
    });

    test('a number starting below 6 is not a mobile', () {
      expect(links('Ref 1234567890 posted'), isEmpty);
    });

    test('an amount is not a phone number', () {
      expect(links('Debited Rs 1234567.00 today'), isEmpty);
    });

    test('a longer digit run is not a phone number', () {
      expect(links('Card ending 6012345678901234'), isEmpty);
    });

    test('a number inside a link stays part of the link', () {
      final found = links('Go to bit.ly/9876543210x now');
      expect(found, hasLength(1));
      expect(found.single.kind, LinkKind.url);
    });
  });

  group('email', () {
    test('finds an address', () {
      expect(first('Write to care@icicibank.com anytime', LinkKind.email),
          'mailto:care@icicibank.com');
    });

    test('the domain half is not also offered as a link', () {
      final found = links('Write to care@icicibank.com/help');
      expect(found.map((p) => p.kind), [LinkKind.email]);
    });
  });

  group('one time codes', () {
    test('finds an OTP when the message says it is one', () {
      expect(MessageLinks.code('123456 is your OTP for login'), '123456');
      expect(MessageLinks.code('Your verification code is 4821'), '4821');
    });

    test('digits without the word are not a code', () {
      expect(MessageLinks.code('Rs 5000 credited to A/c 1234'), isNull);
    });

    test('an amount in an OTP message is not read as the code', () {
      // The decimal point rules the amount out, leaving the real code.
      expect(
        MessageLinks.code('OTP 445566 for txn of Rs 2500.00 at Amazon'),
        '445566',
      );
    });
  });

  group('splitting the body', () {
    test('keeps the text in order and unchanged', () {
      const body = 'Call 9876543210 or visit www.sbi.co.in today';
      final parts = MessageLinks.parse(body);
      expect(parts.map((p) => p.text).join(), body);
      expect(parts.where((p) => p.isLink).map((p) => p.kind),
          [LinkKind.phone, LinkKind.url]);
    });

    test('a message with nothing tappable is one plain part', () {
      final parts = MessageLinks.parse('See you at 8');
      expect(parts, hasLength(1));
      expect(parts.single.isLink, isFalse);
      expect(MessageLinks.hasLinks('See you at 8'), isFalse);
    });

    test('an empty body yields nothing', () {
      expect(MessageLinks.parse(''), isEmpty);
    });

    test('a real bank SMS comes apart correctly', () {
      const body =
          'Dear Customer, Rs.2500.00 debited from A/c XX9012 on 15-09-26. '
          'Not you? Call 1800 266 0101 or visit www.icicibank.com/dispute';
      final found = links(body);
      expect(found.map((p) => p.kind),
          [LinkKind.phone, LinkKind.url]);
      expect(found.first.value, 'tel:18002660101');
      expect(found.last.value, 'https://www.icicibank.com/dispute');
      expect(MessageLinks.parse(body).map((p) => p.text).join(), body);
    });
  });
}
