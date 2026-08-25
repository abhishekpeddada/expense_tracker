import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/providers.dart';
import '../models/models.dart';

final _rupee = NumberFormat.currency(
    locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(transactionsProvider);
    return txns.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        final now = DateTime.now();
        final monthTxns = list
            .where((t) =>
                t.occurredAt.year == now.year && t.occurredAt.month == now.month)
            .toList();

        double spent = 0, received = 0, ccSpent = 0;
        final byCategory = <String, double>{};
        for (final t in monthTxns) {
          if (t.type == TxnType.debit) {
            // Credit card bill payments move money to the card, not out of
            // your pocket twice — exclude them from "spent".
            if (t.category == Categories.creditCardBill) continue;
            spent += t.amount;
            if (t.accountKind == AccountKind.creditCard) ccSpent += t.amount;
            final c = t.category ?? 'Uncategorized';
            byCategory[c] = (byCategory[c] ?? 0) + t.amount;
          } else {
            received += t.amount;
          }
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(DateFormat('MMMM yyyy').format(now),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatCard(
                    label: 'Spent',
                    value: _rupee.format(spent),
                    color: Colors.red.shade700),
                const SizedBox(width: 12),
                _StatCard(
                    label: 'Received',
                    value: _rupee.format(received),
                    color: Colors.green.shade700),
              ],
            ),
            const SizedBox(height: 12),
            _StatCard(
              label: 'Credit card spends',
              value: _rupee.format(ccSpent),
              color: Colors.deepPurple,
              icon: Icons.credit_card,
              expand: false,
            ),
            const SizedBox(height: 24),
            if (byCategory.isNotEmpty) ...[
              Text('By category',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _CategoryPie(byCategory: byCategory),
              const SizedBox(height: 12),
              _CategoryLegend(byCategory: byCategory, total: spent),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Center(
                  child: Text(
                    'No spending recorded this month yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

const _pieColors = [
  Color(0xFF4E79A7),
  Color(0xFFF28E2B),
  Color(0xFFE15759),
  Color(0xFF76B7B2),
  Color(0xFF59A14F),
  Color(0xFFEDC948),
  Color(0xFFB07AA1),
  Color(0xFFFF9DA7),
  Color(0xFF9C755F),
  Color(0xFFBAB0AC),
];

List<MapEntry<String, double>> _sorted(Map<String, double> byCategory) {
  final entries = byCategory.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries;
}

class _CategoryPie extends StatelessWidget {
  final Map<String, double> byCategory;
  const _CategoryPie({required this.byCategory});

  @override
  Widget build(BuildContext context) {
    final entries = _sorted(byCategory);
    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 48,
          sections: [
            for (var i = 0; i < entries.length; i++)
              PieChartSectionData(
                value: entries[i].value,
                color: _pieColors[i % _pieColors.length],
                radius: 52,
                showTitle: false,
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryLegend extends StatelessWidget {
  final Map<String, double> byCategory;
  final double total;
  const _CategoryLegend({required this.byCategory, required this.total});

  @override
  Widget build(BuildContext context) {
    final entries = _sorted(byCategory);
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _pieColors[i % _pieColors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(entries[i].key)),
                Text(_rupee.format(entries[i].value),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    total > 0
                        ? '${(entries[i].value / total * 100).toStringAsFixed(0)}%'
                        : '',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final bool expand;
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    this.icon,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                ],
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
    return expand ? Expanded(child: card) : card;
  }
}
