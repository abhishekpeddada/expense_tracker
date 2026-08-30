/// Cleans up the merchant strings banks put in SMS, which carry reference
/// numbers, payment-rail prefixes and inconsistent casing.
class MerchantName {
  /// A reference label plus its id. The id must contain a digit, otherwise
  /// the pattern would swallow the merchant name that follows the label.
  static final _refRe = RegExp(
    r'\b(refno|ref\s*no|ref|txn\s*id|txnid|txn|transaction\s*id|utr)\b'
    r'[:\s-]*([a-z0-9]*\d[a-z0-9]*)?',
    caseSensitive: false,
  );

  /// Payment-rail words banks prefix to the real merchant name.
  static final _railRe = RegExp(
    r'\b(upi|imps|neft|rtgs|pos|vpa)\b',
    caseSensitive: false,
  );
  static final _longDigitsRe = RegExp(r'\b\d{6,}\b');
  static final _trailingJunkRe = RegExp(r'[\s\-_.,;:/]+$');
  static final _leadingJunkRe = RegExp(r'^[\s\-_.,;:/]+');
  static final _spacesRe = RegExp(r'\s{2,}');

  /// Short words that read wrong in Title Case, so they stay uppercase.
  /// An allowlist rather than a length rule, which would also catch real
  /// words like "PAY".
  static const _acronyms = {
    'ATM', 'WDL', 'EMI', 'NEFT', 'IMPS', 'RTGS', 'ECS', 'GST', 'TDS',
    'SBI', 'HDFC', 'ICICI', 'PNB', 'IOB', 'IDFC', 'RBL', 'INR', 'CC', 'DC',
  };

  /// Human-friendly display name: noise removed, Title Cased.
  /// A VPA (someone@ybl) is left alone — it is already the identifier.
  static String? display(String? raw) {
    if (raw == null) return null;
    final cleaned = _strip(raw);
    if (cleaned.isEmpty) return null;
    if (cleaned.contains('@')) return cleaned;
    return cleaned
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => _acronyms.contains(w.toUpperCase())
            ? w.toUpperCase()
            : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// Stable lookup key for remembering categories. Case- and noise-
  /// insensitive so "SWIGGY BANGALORE" and "Swiggy  Bangalore" match.
  static String? key(String? raw) {
    final cleaned = _strip(raw ?? '').toLowerCase();
    if (cleaned.isEmpty) return null;
    // Merchants often append a city or outlet; the first two words are the
    // stable part ("swiggy bangalore" and "swiggy hyderabad" share "swiggy").
    final words = cleaned.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return null;
    if (cleaned.contains('@')) return cleaned;
    return words.take(2).join(' ');
  }

  static String _strip(String raw) {
    var s = raw.replaceAll(_refRe, ' ').replaceAll(_railRe, ' ');
    s = s.replaceAll(_longDigitsRe, ' ');
    s = s.replaceAll(_spacesRe, ' ');
    s = s.replaceAll(_leadingJunkRe, '');
    s = s.replaceAll(_trailingJunkRe, '');
    return s.trim();
  }
}
