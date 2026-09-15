import 'package:drift/drift.dart' show OrderingTerm;

import '../data/db.dart';
import '../models/models.dart';

/// A debit on one of the user's accounts paired with a credit of the same
/// amount on another, shortly after.
class SelfTransferMatch {
  final Transaction debit;
  final Transaction credit;
  const SelfTransferMatch(this.debit, this.credit);

  Duration get gap =>
      credit.occurredAt.difference(debit.occurredAt).abs();

  double get amount => debit.amount;

  /// Already labelled, so there is nothing to review.
  bool get isSettled =>
      debit.category == Categories.selfTransfer &&
      credit.category == Categories.selfTransfer;

  /// Safe to label without asking: neither side carries a category that
  /// says anything. Null means nobody has decided, and Other is what gets
  /// picked when nothing better fits.
  bool get canApplySilently =>
      SelfTransfers._saysNothing(debit.category) &&
      SelfTransfers._saysNothing(credit.category);

  /// Worth ticking by default on the review screen. Transfer and Refund are
  /// exactly what a self transfer gets mislabelled as, so they are offered;
  /// a deliberate Rent or Salary is shown unticked instead.
  bool get isLikely =>
      SelfTransfers._plausiblyATransfer(debit.category) &&
      SelfTransfers._plausiblyATransfer(credit.category);
}

/// Spots money moved between two accounts the user owns.
///
/// Every transaction the app sees belongs to the user, so a debit leaving
/// one account and an identical credit arriving in another is almost always
/// the same money rather than two unrelated events.
class SelfTransfers {
  /// How far apart the two sides may be. Instant rails settle in seconds,
  /// but a NEFT sent in the morning can land hours later, so this is
  /// generous. The exact-amount and different-account rules do the real
  /// work of keeping matches honest.
  static const window = Duration(hours: 6);

  /// A category carrying no real decision. Other is what the built-in
  /// guesser falls back to when it recognises nothing, so treating it as a
  /// decision would let one bad guess block the pairing forever.
  static bool _saysNothing(String? category) =>
      category == null || category == Categories.other;

  /// Categories a self transfer is commonly filed under by mistake. A
  /// credit is guessed as a Refund when nothing else matches, and a
  /// transfer between accounts is naturally typed as Transfer.
  static bool _plausiblyATransfer(String? category) =>
      _saysNothing(category) ||
      category == Categories.transfer ||
      category == Categories.refund ||
      category == Categories.selfTransfer;

  /// Which account a transaction belongs to, or null when there is not
  /// enough detail to tell one account from another. Without this, two
  /// anonymous transactions could be paired with nothing to say they are
  /// on different accounts.
  static String? accountKey(Transaction t) {
    if (t.bank == null && t.accountTail == null) return null;
    return '${t.bank ?? '?'}|${t.accountTail ?? '?'}|${t.accountKind.index}';
  }

  /// Pairs that look like a self transfer, each transaction used at most
  /// once. Where several credits could match a debit, the closest in time
  /// wins.
  static List<SelfTransferMatch> detect(List<Transaction> all) {
    final debits = <Transaction>[];
    final credits = <Transaction>[];
    for (final t in all) {
      if (accountKey(t) == null) continue;
      (t.type == TxnType.debit ? debits : credits).add(t);
    }
    debits.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    final used = <int>{};
    final matches = <SelfTransferMatch>[];
    for (final debit in debits) {
      final debitAccount = accountKey(debit);
      Transaction? best;
      Duration? bestGap;
      for (final credit in credits) {
        if (used.contains(credit.id)) continue;
        if (credit.amount != debit.amount) continue;
        if (accountKey(credit) == debitAccount) continue;
        final gap = credit.occurredAt.difference(debit.occurredAt).abs();
        if (gap > window) continue;
        if (bestGap == null || gap < bestGap) {
          best = credit;
          bestGap = gap;
        }
      }
      if (best != null) {
        used.add(best.id);
        matches.add(SelfTransferMatch(debit, best));
      }
    }
    return matches;
  }

  /// Pairs still worth showing the user: detected, and not already labelled
  /// on both sides.
  static List<SelfTransferMatch> suggestions(List<Transaction> all) =>
      [for (final m in detect(all)) if (!m.isSettled) m];

  /// Labels the pairs that need no judgement, and answers how many.
  ///
  /// A category the user chose, or one learned from their own past choices,
  /// outranks this guess, so those pairs are left for [suggestions] and the
  /// review screen instead of being overwritten here.
  static Future<int> apply(AppDb db) async {
    final all = await _allTransactions(db);

    var labelled = 0;
    for (final match in detect(all)) {
      if (match.isSettled || !match.canApplySilently) continue;
      await label(db, match);
      labelled++;
    }
    return labelled;
  }

  /// Labels one pair, whatever it was categorized as before. Used by the
  /// review screen, where the user has seen both sides and said yes.
  static Future<void> label(AppDb db, SelfTransferMatch match) async {
    await db.setCategory(match.debit.id, Categories.selfTransfer);
    await db.setCategory(match.credit.id, Categories.selfTransfer);
  }

  static Future<List<Transaction>> _allTransactions(AppDb db) =>
      (db.select(db.transactions)
            ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
          .get();
}
