import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _dateFmt = DateFormat('d MMM, h:mm a');

class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(transactionsProvider);
    return txns.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyState(
            icon: Icons.receipt_long,
            title: 'No transactions yet',
            subtitle:
                'When a bank SMS arrives it will be parsed and show up here.',
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) => TransactionTile(txn: list[i]),
        );
      },
    );
  }
}

class TransactionTile extends ConsumerWidget {
  final Transaction txn;
  const TransactionTile({super.key, required this.txn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDebit = txn.type == TxnType.debit;
    final color = isDebit ? Colors.red.shade700 : Colors.green.shade700;
    final uncategorized = txn.category == null;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(
          txn.accountKind == AccountKind.creditCard
              ? Icons.credit_card
              : (isDebit ? Icons.arrow_upward : Icons.arrow_downward),
          color: color,
        ),
      ),
      title: Text(txn.merchant ?? txn.bank ?? 'Unknown'),
      subtitle: Text(
        [
          _dateFmt.format(txn.occurredAt),
          if (txn.accountTail != null)
            '${txn.accountKind == AccountKind.creditCard ? "Card" : "A/c"} '
                '••${txn.accountTail}',
          txn.category ?? 'Tap to categorize',
        ].join(' · '),
        style: uncategorized
            ? TextStyle(color: Theme.of(context).colorScheme.primary)
            : null,
      ),
      trailing: Text(
        '${isDebit ? '-' : '+'}${_rupee.format(txn.amount)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      onTap: () => showCategorySheet(context, ref, txn),
    );
  }
}

/// Bottom sheet asking "what is this transaction about?" — the in-app
/// counterpart of the persistent notification.
Future<void> showCategorySheet(
    BuildContext context, WidgetRef ref, Transaction txn) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'What was ${_rupee.format(txn.amount)}'
              '${txn.merchant != null ? ' at ${txn.merchant}' : ''} for?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in Categories.all)
                  ChoiceChip(
                    label: Text(c),
                    selected: txn.category == c,
                    onSelected: (_) async {
                      await ref.read(dbProvider).setCategory(txn.id, c);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
