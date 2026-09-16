import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../services/self_transfer.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹',
    decimalDigits: 0);
final _when = DateFormat('d MMM, h:mm a');

/// Pairs that look like a self transfer but are already filed under
/// something else.
///
/// Auto-labelling deliberately never overwrites a category, which leaves a
/// gap: a transfer categorized long ago, or one whose merchant has a
/// learned rule, would stay counted as spending forever. This is where
/// those get fixed, in bulk, with both sides visible.
class SelfTransfersPage extends ConsumerStatefulWidget {
  const SelfTransfersPage({super.key});

  @override
  ConsumerState<SelfTransfersPage> createState() => _SelfTransfersPageState();
}

class _SelfTransfersPageState extends ConsumerState<SelfTransfersPage> {
  /// Debit ids of the pairs ticked for relabelling. Seeded from the
  /// likely-looking ones the first time the list arrives.
  final _chosen = <int>{};
  bool _seeded = false;
  bool _busy = false;

  Future<void> _apply(List<SelfTransferMatch> matches) async {
    final picked =
        matches.where((m) => _chosen.contains(m.debit.id)).toList();
    if (picked.isEmpty) return;

    setState(() => _busy = true);
    final db = ref.read(dbProvider);
    final messenger = ScaffoldMessenger.of(context);
    for (final match in picked) {
      await SelfTransfers.label(db, match);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _chosen.clear();
    });
    messenger.showSnackBar(SnackBar(
      content: Text('${picked.length} pair${picked.length == 1 ? '' : 's'} '
          'no longer counted as spending'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final matches = ref.watch(selfTransferSuggestionsProvider);

    if (!_seeded && matches.isNotEmpty) {
      _seeded = true;
      _chosen.addAll(
          [for (final m in matches) if (m.isLikely) m.debit.id]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Possible self transfers')),
      body: matches.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 56,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Nothing to review',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Every matching pair is already labelled as a self '
                      'transfer and left out of your totals.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  'Each of these is money leaving one of your accounts and '
                  'the same amount arriving in another within '
                  '${SelfTransfers.window.inHours} hours. They are already '
                  'filed under something else, so they are still being '
                  'counted. Tick the ones that were you moving your own '
                  'money.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      if (_chosen.length == matches.length) {
                        _chosen.clear();
                      } else {
                        _chosen
                          ..clear()
                          ..addAll(matches.map((m) => m.debit.id));
                      }
                    }),
                    child: Text(_chosen.length == matches.length
                        ? 'Clear all'
                        : 'Select all'),
                  ),
                ),
                for (final m in matches)
                  _PairCard(
                    match: m,
                    selected: _chosen.contains(m.debit.id),
                    onChanged: () => setState(() {
                      if (!_chosen.remove(m.debit.id)) {
                        _chosen.add(m.debit.id);
                      }
                    }),
                  ),
              ],
            ),
      bottomNavigationBar: matches.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed:
                      _busy || _chosen.isEmpty ? null : () => _apply(matches),
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.swap_horiz),
                  label: Text(_chosen.isEmpty
                      ? 'Nothing selected'
                      : 'Mark ${_chosen.length} as self transfer'),
                ),
              ),
            ),
    );
  }
}

class _PairCard extends StatelessWidget {
  final SelfTransferMatch match;
  final bool selected;
  final VoidCallback onChanged;

  const _PairCard({
    required this.match,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gap = match.gap;
    final gapLabel = gap.inMinutes < 1
        ? 'same minute'
        : gap.inMinutes < 60
            ? '${gap.inMinutes} min apart'
            : '${gap.inHours} h apart';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onChanged,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Checkbox(value: selected, onChanged: (_) => onChanged()),
                  Expanded(
                    child: Text(
                      _money.format(match.amount),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(gapLabel,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  children: [
                    _Leg(txn: match.debit, outgoing: true),
                    const SizedBox(height: 6),
                    _Leg(txn: match.credit, outgoing: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One side of a pair: where it went, and what it is filed under today.
class _Leg extends StatelessWidget {
  final Transaction txn;
  final bool outgoing;
  const _Leg({required this.txn, required this.outgoing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final account = [
      ?txn.bank,
      if (txn.accountTail != null) 'x${txn.accountTail}',
    ].join(' ');
    final category = txn.category;

    return Row(
      children: [
        Icon(outgoing ? Icons.arrow_upward : Icons.arrow_downward,
            size: 16,
            color: outgoing ? scheme.error : scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            [
              account.isEmpty ? 'Unknown account' : account,
              _when.format(txn.occurredAt),
              ?txn.merchant,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (category != null && !Categories.isInternal(category))
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Chip(
              label: Text(category,
                  style: Theme.of(context).textTheme.labelSmall),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }
}
