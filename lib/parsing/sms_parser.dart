import '../models/models.dart';

/// Result of parsing a bank/UPI SMS into a transaction candidate.
class ParsedTransaction {
  final double amount;
  final TxnType type;
  final AccountKind accountKind;

  /// Last-4 digits (or masked tail) of the account/card, if present.
  final String? accountTail;

  /// Merchant / counterparty, if the SMS names one.
  final String? merchant;

  /// Bank name guessed from the message body, if any.
  final String? bank;

  /// Balance after the transaction ("Avl bal") for bank accounts, or the
  /// available limit for credit cards, when the SMS states one.
  final double? balance;

  const ParsedTransaction({
    required this.amount,
    required this.type,
    required this.accountKind,
    this.accountTail,
    this.merchant,
    this.bank,
    this.balance,
  });

  @override
  String toString() =>
      'ParsedTransaction(amount: $amount, type: $type, kind: $accountKind, '
      'tail: $accountTail, merchant: $merchant, bank: $bank)';
}

/// Parses Indian bank / card / UPI SMS messages into [ParsedTransaction]s.
///
/// Returns null for anything that is not a money-movement message (OTPs,
/// promos, balance updates, payment reminders).
class SmsParser {
  static final _amountRe = RegExp(
    r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// Many banks (SBI's UPI alerts especially) state the amount with no
  /// currency symbol at all: "A/C X5942 debited by 1.00". Fall back to the
  /// number sitting next to the debit/credit verb.
  static final _amountNearVerbRe = RegExp(
    r'\b(?:debited|credited|spent|paid|sent|withdrawn|deducted|received|'
    r'debit|credit)\s*(?:by|for|with|of|:)?\s*'
    r'(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)\b',
    caseSensitive: false,
  );

  static final _debitRe = RegExp(
    r'\b(debited|spent|paid|withdrawn|purchase(?:\s+of)?|sent|deducted)\b',
    caseSensitive: false,
  );

  static final _creditRe = RegExp(
    r'\b(credited|received|deposited|refund(?:ed)?|reversed|cashback)\b',
    caseSensitive: false,
  );

  // Messages that mention money but are not transactions.
  static final _rejectRe = RegExp(
    r'\b(otp|one\s*time\s*password|will\s+be\s+debited|due\s+(?:on|by)|'
    r'min(?:imum)?\s+due|e-?mandate|autopay\s+is\s+set|offer|win|'
    r'loan\s+(?:offer|approved\s+offer)|apply\s+now|last\s+date|'
    r'requested\s+money|has\s+requested|payment\s+request|collect\s+request)\b',
    caseSensitive: false,
  );

  static final _creditCardRe = RegExp(
    r'credit\s*card|\bcc\b(?:\s+ending|\s*x+\d)|card\s+(?:no\.?\s*)?(?:ending|xx)',
    caseSensitive: false,
  );

  static final _balanceRe = RegExp(
    r'(?:avl|available|avail\.?)\s*(?:bal(?:ance)?|limit)\s*:?\s*'
    r'(?:is\s+)?(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  static final _accountTailRe = RegExp(
    r'(?:a/c|acct|account|card)\s*(?:no\.?\s*)?(?:ending\s*(?:in\s*)?|[x*]+)(\d{3,6})',
    caseSensitive: false,
  );

  static final _merchantAtRe = RegExp(
    r'\bat\s+([A-Za-z0-9][A-Za-z0-9 &._\-*]{2,40}?)(?=\s+on\b|\s+via\b|\.\s|\.$|,|$)',
    caseSensitive: false,
  );

  static final _merchantToRe = RegExp(
    r'\b(?:to|towards)\s+(?:vpa\s+)?([A-Za-z0-9][A-Za-z0-9 @._\-]{2,40}?)(?=\s+on\b|\s+via\b|\s+ref|\s+upi\b|\.\s|\.$|,|$)',
    caseSensitive: false,
  );

  static final _merchantFromRe = RegExp(
    r'\bfrom\s+(?:vpa\s+)?([A-Za-z0-9][A-Za-z0-9 @._\-]{2,40}?)(?=\s+on\b|\s+via\b|\s+ref|\s+upi\b|\.\s|\.$|,|$)',
    caseSensitive: false,
  );

  static const _banks = {
    'hdfc': 'HDFC Bank',
    'icici': 'ICICI Bank',
    'sbi': 'SBI',
    'axis': 'Axis Bank',
    'kotak': 'Kotak',
    'pnb': 'PNB',
    'canara': 'Canara Bank',
    'idfc': 'IDFC First',
    'yes bank': 'Yes Bank',
    'indusind': 'IndusInd',
    'federal': 'Federal Bank',
    'bob': 'Bank of Baroda',
    'union bank': 'Union Bank',
  };

  /// Parse [body]; [sender] (e.g. "VM-HDFCBK-S") helps bank detection.
  static ParsedTransaction? parse(String body, {String? sender}) {
    final text = body.replaceAll('\n', ' ');

    if (_rejectRe.hasMatch(text)) return null;

    final amountMatch =
        _amountRe.firstMatch(text) ?? _amountNearVerbRe.firstMatch(text);
    if (amountMatch == null) return null;
    final amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) return null;

    final isDebit = _debitRe.hasMatch(text);
    final isCredit = _creditRe.hasMatch(text);
    if (!isDebit && !isCredit) return null;
    // "Refund credited" style messages are credits even if a debit word
    // appears earlier; prefer whichever keyword appears first.
    late final TxnType type;
    if (isDebit && isCredit) {
      final d = _debitRe.firstMatch(text)!.start;
      final c = _creditRe.firstMatch(text)!.start;
      type = d < c ? TxnType.debit : TxnType.credit;
    } else {
      type = isDebit ? TxnType.debit : TxnType.credit;
    }

    final kind =
        _creditCardRe.hasMatch(text) ? AccountKind.creditCard : AccountKind.bank;

    final tail = _accountTailRe.firstMatch(text)?.group(1);

    String? merchant;
    if (type == TxnType.debit) {
      merchant = _merchantAtRe.firstMatch(text)?.group(1) ??
          _merchantToRe.firstMatch(text)?.group(1);
    } else {
      merchant = _merchantFromRe.firstMatch(text)?.group(1);
    }
    merchant = merchant?.trim();
    if (merchant != null && merchant.isEmpty) merchant = null;

    String? bank;
    final haystack = '${sender ?? ''} $text'.toLowerCase();
    for (final e in _banks.entries) {
      if (haystack.contains(e.key)) {
        bank = e.value;
        break;
      }
    }

    final balance = double.tryParse(
        _balanceRe.firstMatch(text)?.group(1)?.replaceAll(',', '') ?? '');

    return ParsedTransaction(
      amount: amount,
      type: type,
      accountKind: kind,
      accountTail: tail,
      merchant: merchant,
      bank: bank,
      balance: balance,
    );
  }

  /// A quick guess at a category so the notification can pre-select one.
  static String suggestCategory(ParsedTransaction t) {
    final m = (t.merchant ?? '').toLowerCase();
    if (t.type == TxnType.credit) {
      if (m.contains('salary')) return Categories.salary;
      return Categories.refund;
    }
    if (m.contains('swiggy') || m.contains('zomato') || m.contains('domino')) {
      return Categories.food;
    }
    if (m.contains('bigbasket') || m.contains('blinkit') || m.contains('zepto') ||
        m.contains('dmart') || m.contains('grofers')) {
      return Categories.groceries;
    }
    if (m.contains('uber') || m.contains('ola') || m.contains('rapido') ||
        m.contains('irctc') || m.contains('makemytrip') || m.contains('redbus')) {
      return Categories.travel;
    }
    if (m.contains('amazon') || m.contains('flipkart') || m.contains('myntra') ||
        m.contains('ajio')) {
      return Categories.shopping;
    }
    if (m.contains('netflix') || m.contains('spotify') || m.contains('hotstar') ||
        m.contains('bookmyshow')) {
      return Categories.entertainment;
    }
    if (m.contains('electricity') || m.contains('recharge') ||
        m.contains('jio') || m.contains('airtel') || m.contains('vi ')) {
      return Categories.bills;
    }
    if (m.contains('pharm') || m.contains('apollo') || m.contains('hospital')) {
      return Categories.health;
    }
    return Categories.other;
  }
}
