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

  /// Categorizes matched pairs as self transfers, and answers how many
  /// pairs were labelled.
  ///
  /// Only pairs where neither side has been categorized are touched: a
  /// category the user chose, or one learned from their own past choices,
  /// always outranks this guess. A wrong guess is visible on the
  /// Transactions tab and can be changed like any other.
  static Future<int> apply(AppDb db) async {
    final all = await (db.select(db.transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .get();

    var labelled = 0;
    for (final match in detect(all)) {
      if (match.debit.category != null || match.credit.category != null) {
        continue;
      }
      await db.setCategory(match.debit.id, Categories.selfTransfer);
      await db.setCategory(match.credit.id, Categories.selfTransfer);
      labelled++;
    }
    return labelled;
  }
}
