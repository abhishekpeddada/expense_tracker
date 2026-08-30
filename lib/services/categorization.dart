import '../data/db.dart';
import '../parsing/merchant.dart';
import '../parsing/sms_parser.dart';

/// Decides a category for a transaction, preferring what the user has taught
/// the app over the built-in merchant guesses.
class Categorizer {
  Categorizer(this._db);

  final AppDb _db;

  /// A learned category for this merchant, or null if none is known.
  /// Built-in guesses are deliberately not consulted here: they are only a
  /// suggestion for the notification, never applied silently.
  Future<String?> learnedCategory(String? merchant) async {
    final key = MerchantName.key(merchant);
    if (key == null) return null;
    return _db.categoryForMerchant(key);
  }

  /// Records the user's choice so the next transaction from this merchant is
  /// categorized on its own.
  Future<void> learn(String? merchant, String category) async {
    final key = MerchantName.key(merchant);
    if (key == null) return;
    await _db.rememberCategory(key, category);
  }

  /// Sets the category on one transaction and learns from it.
  Future<void> apply(Transaction txn, String category) async {
    await _db.setCategory(txn.id, category);
    await learn(txn.merchant, category);
  }

  /// Applies a learned rule to a freshly ingested transaction. Returns the
  /// category applied, or null when nothing is known yet.
  Future<String?> autoCategorize(int txnId, String? merchant) async {
    final learned = await learnedCategory(merchant);
    if (learned == null) return null;
    await _db.setCategory(txnId, learned);
    return learned;
  }

  /// Back-fills every uncategorized transaction whose merchant is now known.
  /// Run after the user teaches a new rule.
  Future<int> applyRulesToUncategorized() async {
    final pending = await _db.watchUncategorized().first;
    var applied = 0;
    for (final t in pending) {
      final learned = await learnedCategory(t.merchant);
      if (learned != null) {
        await _db.setCategory(t.id, learned);
        applied++;
      }
    }
    return applied;
  }

  /// The suggestion shown before the user has taught anything — the built-in
  /// merchant list.
  static String suggest(ParsedTransaction parsed) =>
      SmsParser.suggestCategory(parsed);
}
