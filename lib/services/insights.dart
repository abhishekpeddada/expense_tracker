import '../data/db.dart';
import '../models/models.dart';

class Insight {
  final String text;
  final InsightTone tone;
  const Insight(this.text, [this.tone = InsightTone.neutral]);
}

enum InsightTone { good, neutral, warning }

/// A recurring payment: the same merchant charging a similar amount on a
/// regular cadence.
class Recurring {
  final String merchant;
  final double typicalAmount;
  final int occurrences;
  final DateTime lastSeen;
  final int averageGapDays;

  const Recurring({
    required this.merchant,
    required this.typicalAmount,
    required this.occurrences,
    required this.lastSeen,
    required this.averageGapDays,
  });

  String get cadence {
    if (averageGapDays <= 9) return 'weekly';
    if (averageGapDays <= 17) return 'fortnightly';
    if (averageGapDays <= 45) return 'monthly';
    if (averageGapDays <= 100) return 'quarterly';
    return 'occasional';
  }
}

/// Derives plain-language observations from transaction history. Runs
/// entirely on-device: no network, no key, and the data never leaves
/// the phone.
class Insights {
  static double _spend(Iterable<Transaction> txns) => txns
      .where((t) =>
          t.type == TxnType.debit && t.category != Categories.creditCardBill)
      .fold(0.0, (sum, t) => sum + t.amount);

  static List<Transaction> _inMonth(
          List<Transaction> all, DateTime month) =>
      all
          .where((t) =>
              t.occurredAt.year == month.year &&
              t.occurredAt.month == month.month)
          .toList();

  static Map<String, double> byCategory(Iterable<Transaction> txns) {
    final out = <String, double>{};
    for (final t in txns) {
      if (t.type != TxnType.debit) continue;
      if (t.category == Categories.creditCardBill) continue;
      final c = t.category ?? 'Uncategorized';
      out[c] = (out[c] ?? 0) + t.amount;
    }
    return out;
  }

  /// Total spend per month, oldest first, for the trend chart.
  static List<MapEntry<DateTime, double>> monthlyTotals(
    List<Transaction> all, {
    int months = 6,
  }) {
    final now = DateTime.now();
    final out = <MapEntry<DateTime, double>>[];
    for (var i = months - 1; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i);
      out.add(MapEntry(m, _spend(_inMonth(all, m))));
    }
    return out;
  }

  /// Observations about the given month compared with the one before it.
  static List<Insight> forMonth(List<Transaction> all, DateTime month) {
    final current = _inMonth(all, month);
    final previous =
        _inMonth(all, DateTime(month.year, month.month - 1));
    final out = <Insight>[];

    final spent = _spend(current);
    if (current.isEmpty) return const [Insight('No transactions this month.')];

    final prevSpent = _spend(previous);
    if (previous.isNotEmpty && prevSpent > 0) {
      final delta = (spent - prevSpent) / prevSpent * 100;
      if (delta.abs() >= 10) {
        final word = delta > 0 ? 'more' : 'less';
        out.add(Insight(
          'You spent ${delta.abs().round()}% $word than last month '
          '(${_money(spent)} vs ${_money(prevSpent)}).',
          delta > 0 ? InsightTone.warning : InsightTone.good,
        ));
      } else {
        out.add(Insight(
          'Spending is about the same as last month (${_money(spent)}).',
        ));
      }
    }

    final cats = byCategory(current);
    if (cats.isNotEmpty) {
      final top = cats.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final share = spent > 0 ? (top.value / spent * 100).round() : 0;
      out.add(Insight(
        '${top.key} is your biggest category at ${_money(top.value)}, '
        '$share% of the month.',
      ));

      // Categories that grew most against last month.
      final prevCats = byCategory(previous);
      String? worstName;
      double worstDelta = 0;
      for (final e in cats.entries) {
        final before = prevCats[e.key] ?? 0;
        if (before <= 0) continue;
        final d = (e.value - before) / before * 100;
        if (d > worstDelta) {
          worstDelta = d;
          worstName = e.key;
        }
      }
      if (worstName != null && worstDelta >= 25) {
        out.add(Insight(
          '$worstName is up ${worstDelta.round()}% versus last month.',
          InsightTone.warning,
        ));
      }
    }

    final uncategorized =
        current.where((t) => t.category == null).length;
    if (uncategorized > 0) {
      out.add(Insight(
        '$uncategorized transaction${uncategorized == 1 ? '' : 's'} still '
        'need a category.',
      ));
    }

    final biggest = current
        .where((t) => t.type == TxnType.debit)
        .fold<Transaction?>(
            null, (a, b) => a == null || b.amount > a.amount ? b : a);
    if (biggest != null && biggest.merchant != null) {
      out.add(Insight(
        'Largest single spend: ${_money(biggest.amount)} at '
        '${biggest.merchant}.',
      ));
    }

    final received = current
        .where((t) => t.type == TxnType.credit)
        .fold(0.0, (s, t) => s + t.amount);
    if (received > 0 && spent > 0) {
      final net = received - spent;
      out.add(Insight(
        net >= 0
            ? 'You are ${_money(net)} up this month.'
            : 'You are ${_money(-net)} down this month.',
        net >= 0 ? InsightTone.good : InsightTone.warning,
      ));
    }

    return out;
  }

  /// Merchants charging repeatedly on a regular cadence.
  static List<Recurring> recurring(List<Transaction> all) {
    final byMerchant = <String, List<Transaction>>{};
    for (final t in all) {
      if (t.type != TxnType.debit) continue;
      final m = t.merchant;
      if (m == null || m.isEmpty) continue;
      byMerchant.putIfAbsent(m, () => []).add(t);
    }

    final out = <Recurring>[];
    for (final entry in byMerchant.entries) {
      final txns = entry.value..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      if (txns.length < 3) continue;

      // Amounts should cluster: a subscription is the same price each time.
      final amounts = txns.map((t) => t.amount).toList();
      final median = (amounts.toList()..sort())[amounts.length ~/ 2];
      if (median <= 0) continue;
      final consistent = amounts
          .where((a) => (a - median).abs() / median <= 0.15)
          .length;
      if (consistent < 3) continue;

      final gaps = <int>[];
      for (var i = 1; i < txns.length; i++) {
        gaps.add(txns[i].occurredAt.difference(txns[i - 1].occurredAt).inDays);
      }
      if (gaps.isEmpty) continue;
      final avgGap = gaps.reduce((a, b) => a + b) ~/ gaps.length;
      if (avgGap < 5 || avgGap > 100) continue;

      // Gaps must be regular, not merely frequent.
      final irregular =
          gaps.where((g) => (g - avgGap).abs() > avgGap * 0.4).length;
      if (irregular > gaps.length / 2) continue;

      out.add(Recurring(
        merchant: entry.key,
        typicalAmount: median,
        occurrences: txns.length,
        lastSeen: txns.last.occurredAt,
        averageGapDays: avgGap,
      ));
    }
    out.sort((a, b) => b.typicalAmount.compareTo(a.typicalAmount));
    return out;
  }

  static String _money(double v) => '₹${v.toStringAsFixed(0)}';
}
