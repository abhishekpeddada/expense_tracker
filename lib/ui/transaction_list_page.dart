import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';
import 'delete_transaction.dart';
import 'transactions_page.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

/// What a dashboard figure was made of.
///
/// This is a description rather than a snapshot of rows, so the list stays
/// live: deleting or recategorizing something here updates the list and the
/// total underneath it straight away.
class TxnFilter {
  /// The month the figure covered, or null for all time.
  final DateTime? month;

  /// An explicit window instead of a calendar month, for a figure that
  /// does not line up with one — a credit card statement period. [from] is
  /// inclusive, [toExclusive] is not, and setting either ignores [month].
  final DateTime? from;
  final DateTime? toExclusive;

  /// What to call that window in the heading.
  final String? periodLabel;

  final TxnType? type;
  final bool creditCardOnly;

  /// Exact category string, matched as stored.
  final String? category;

  /// The pie lumps everything without a category into one slice, so that
  /// slice needs a filter for "no category at all" rather than a name.
  final bool uncategorizedOnly;

  /// Leave out self transfers and card bill payments, matching how the
  /// dashboard totals are worked out.
  final bool excludeInternal;

  /// Show only those, which is what the "moved between your own accounts"
  /// line adds up to.
  final bool onlyInternal;

  const TxnFilter({
    this.month,
    this.from,
    this.toExclusive,
    this.periodLabel,
    this.type,
    this.creditCardOnly = false,
    this.category,
    this.uncategorizedOnly = false,
    this.excludeInternal = true,
    this.onlyInternal = false,
  });

  bool get hasWindow => from != null || toExclusive != null;

  bool matches(Transaction t) {
    if (hasWindow) {
      if (from != null && t.occurredAt.isBefore(from!)) return false;
      if (toExclusive != null && !t.occurredAt.isBefore(toExclusive!)) {
        return false;
      }
    } else if (month != null &&
        (t.occurredAt.year != month!.year ||
            t.occurredAt.month != month!.month)) {
      return false;
    }
    final internal = Categories.isInternal(t.category);
    if (onlyInternal && !internal) return false;
    if (excludeInternal && !onlyInternal && internal) return false;
    if (type != null && t.type != type) return false;
    if (creditCardOnly && t.accountKind != AccountKind.creditCard) {
      return false;
    }
    if (uncategorizedOnly) return t.category == null;
    if (category != null && t.category != category) return false;
    return true;
  }
}

class TransactionListPage extends ConsumerWidget {
  final String title;
  final TxnFilter filter;

  const TransactionListPage({
    super.key,
    required this.title,
    required this.filter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(transactionsProvider).valueOrNull ??
        const <Transaction>[];
    final list = [for (final t in all) if (filter.matches(t)) t];
    final total = list.fold<double>(0, (sum, t) => sum + t.amount);

    final period = filter.periodLabel ??
        (filter.month == null
            ? 'All time'
            : DateFormat('MMMM yyyy').format(filter.month!));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18)),
            Text(period, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Nothing here for $period.',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                          '${list.length} '
                          'transaction${list.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const Spacer(),
                      Text(_rupee.format(total),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final txn = list[i];
                      return Dismissible(
                        key: ValueKey('drill-${txn.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red.shade700,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child:
                              const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) =>
                            confirmDeleteTransaction(context, txn),
                        onDismissed: (_) => deleteTransactionWithUndo(
                            ScaffoldMessenger.of(context), ref, txn),
                        child: TransactionTile(txn: txn),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
