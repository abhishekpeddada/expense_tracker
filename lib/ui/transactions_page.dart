import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';
import 'transaction_edit_page.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _dateFmt = DateFormat('d MMM, h:mm a');

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _category;
  TxnType? _type;
  bool _uncategorizedOnly = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasFilters =>
      _category != null || _type != null || _uncategorizedOnly;

  List<Transaction> _apply(List<Transaction> all) {
    final q = _query.trim().toLowerCase();
    return all.where((t) {
      if (_uncategorizedOnly && t.category != null) return false;
      if (_category != null && t.category != _category) return false;
      if (_type != null && t.type != _type) return false;
      if (q.isEmpty) return true;
      return (t.merchant ?? '').toLowerCase().contains(q) ||
          (t.bank ?? '').toLowerCase().contains(q) ||
          (t.category ?? '').toLowerCase().contains(q) ||
          (t.note ?? '').toLowerCase().contains(q) ||
          (t.smsSender ?? '').toLowerCase().contains(q) ||
          t.amount.toStringAsFixed(2).contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(transactionsProvider);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search merchant, category, amount',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                FilterChip(
                  label: const Text('Uncategorized'),
                  selected: _uncategorizedOnly,
                  onSelected: (v) => setState(() => _uncategorizedOnly = v),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Spent'),
                  selected: _type == TxnType.debit,
                  onSelected: (v) =>
                      setState(() => _type = v ? TxnType.debit : null),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Received'),
                  selected: _type == TxnType.credit,
                  onSelected: (v) =>
                      setState(() => _type = v ? TxnType.credit : null),
                ),
                const SizedBox(width: 8),
                for (final c in Categories.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (v) =>
                          setState(() => _category = v ? c : null),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: txns.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                if (all.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.receipt_long,
                    title: 'No transactions yet',
                    subtitle: 'Bank SMS are parsed automatically, or add one '
                        'by hand with the button below.',
                  );
                }
                final list = _apply(all);
                if (list.isEmpty) {
                  return _EmptyState(
                    icon: Icons.filter_alt_off,
                    title: 'Nothing matches',
                    subtitle: _hasFilters || _query.isNotEmpty
                        ? 'Try clearing the search or filters.'
                        : '',
                  );
                }

                final total = list
                    .where((t) => t.type == TxnType.debit)
                    .fold<double>(0, (s, t) => s + t.amount);

                return Column(
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: [
                          Text('${list.length} shown',
                              style: Theme.of(context).textTheme.bodySmall),
                          const Spacer(),
                          Text('${_rupee.format(total)} spent',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final txn = list[i];
                          return Dismissible(
                            key: ValueKey('txn-${txn.id}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red.shade700,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child:
                                  const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) async {
                              await ref
                                  .read(dbProvider)
                                  .deleteTransaction(txn.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Transaction deleted')),
                                );
                              }
                            },
                            child: TransactionTile(txn: txn),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TransactionEditPage()),
        ),
        child: const Icon(Icons.add),
      ),
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
      title: Text(txn.merchant ?? txn.bank ?? txn.smsSender ?? 'Unknown'),
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
      onLongPress: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransactionEditPage(existing: txn),
        ),
      ),
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
    isScrollControlled: true,
    builder: (context) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'What was ${_rupee.format(txn.amount)}'
                    '${txn.merchant != null ? ' at ${txn.merchant}' : ''} for?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit transaction',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TransactionEditPage(existing: txn),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Delete transaction',
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                  onPressed: () async {
                    await ref.read(dbProvider).deleteTransaction(txn.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
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
                      final n = await _applyAndLearn(ref, txn, c);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      if (n > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'Also categorized $n earlier transaction'
                              '${n == 1 ? '' : 's'} from this merchant'),
                        ));
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Or type your own category',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.words,
              onSubmitted: (value) async {
                final custom = value.trim();
                if (custom.isEmpty) return;
                await _applyAndLearn(ref, txn, custom);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      ),
    ),
  );
}

/// Applies a category, remembers it for this merchant, and back-fills any
/// other uncategorized transactions from the same merchant. Returns how many
/// earlier transactions were filled in.
Future<int> _applyAndLearn(
    WidgetRef ref, Transaction txn, String category) async {
  final categorizer = ref.read(categorizerProvider);
  await categorizer.apply(txn, category);
  return categorizer.applyRulesToUncategorized();
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
