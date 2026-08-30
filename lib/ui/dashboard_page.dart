import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../services/insights.dart';
import 'budgets_page.dart';

final _rupee = NumberFormat.currency(
    locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  /// Selected period as (year, month); null month means the whole year,
  /// null selection means every transaction ever recorded.
  DateTime? _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _allTime = false;

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(transactionsProvider);
    return txns.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        // Months that actually have data, newest first — history is never
        // deleted, so past months stay selectable forever.
        final months = <DateTime>{
          for (final t in list) DateTime(t.occurredAt.year, t.occurredAt.month),
        }.toList()
          ..sort((a, b) => b.compareTo(a));

        final now = DateTime.now();
        final thisMonth = DateTime(now.year, now.month);
        if (!months.contains(thisMonth)) months.insert(0, thisMonth);

        // Keep the selection valid if the chosen month scrolled out of data.
        var selected = _month;
        if (!_allTime && (selected == null || !months.contains(selected))) {
          selected = months.first;
        }

        final monthTxns = _allTime
            ? list
            : list
                .where((t) =>
                    t.occurredAt.year == selected!.year &&
                    t.occurredAt.month == selected.month)
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    _allTime
                        ? 'All time'
                        : DateFormat('MMMM yyyy').format(selected!),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                DropdownButton<String>(
                  value: _allTime ? 'all' : selected!.toIso8601String(),
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    for (final m in months)
                      DropdownMenuItem(
                        value: m.toIso8601String(),
                        child: Text(DateFormat('MMM yyyy').format(m)),
                      ),
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All time'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      if (v == 'all') {
                        _allTime = true;
                      } else {
                        _allTime = false;
                        _month = DateTime.parse(v);
                      }
                    });
                  },
                ),
              ],
            ),
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
            const SizedBox(height: 20),
            _InsightsCard(
              insights: Insights.forMonth(
                  list, _allTime ? DateTime(now.year, now.month) : selected!),
            ),
            const SizedBox(height: 20),
            _BudgetProgress(spendByCategory: byCategory),
            const SizedBox(height: 20),
            _TrendChart(totals: Insights.monthlyTotals(list)),
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
                    _allTime
                        ? 'No spending recorded yet.'
                        : 'No spending recorded for this month.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            _RecurringCard(items: Insights.recurring(list)),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

/// Plain-language observations about the selected month.
class _InsightsCard extends StatelessWidget {
  final List<Insight> insights;
  const _InsightsCard({required this.insights});

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Summary',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            for (final i in insights)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 8),
                      child: Icon(Icons.circle, size: 7,
                          color: switch (i.tone) {
                            InsightTone.good => Colors.green.shade600,
                            InsightTone.warning => Colors.orange.shade700,
                            InsightTone.neutral => scheme.outline,
                          }),
                    ),
                    Expanded(child: Text(i.text)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Six-month spend trend, so direction is visible at a glance.
class _TrendChart extends StatelessWidget {
  final List<MapEntry<DateTime, double>> totals;
  const _TrendChart({required this.totals});

  @override
  Widget build(BuildContext context) {
    final maxY = totals.fold<double>(0, (m, e) => e.value > m ? e.value : m);
    if (maxY <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last 6 months',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  maxY: maxY * 1.2,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(),
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= totals.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('MMM').format(totals[i].key),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                        _rupee.format(rod.toY),
                        TextStyle(color: scheme.onInverseSurface),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < totals.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: totals[i].value,
                          color: i == totals.length - 1
                              ? scheme.primary
                              : scheme.primary.withValues(alpha: 0.4),
                          width: 18,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4)),
                        ),
                      ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Budget bars for categories that have a limit set.
class _BudgetProgress extends ConsumerWidget {
  final Map<String, double> spendByCategory;
  const _BudgetProgress({required this.spendByCategory});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const <Budget>[];
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Budgets',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BudgetsPage()),
                  ),
                  child: Text(budgets.isEmpty ? 'Set up' : 'Edit'),
                ),
              ],
            ),
            if (budgets.isEmpty)
              Text(
                'Set a monthly cap per category to get warned before you '
                'overshoot.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              for (final b in budgets)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Builder(builder: (context) {
                    final spent = spendByCategory[b.category] ?? 0;
                    final ratio = b.monthlyLimit <= 0
                        ? 0.0
                        : (spent / b.monthlyLimit).clamp(0.0, 1.0);
                    final over = spent > b.monthlyLimit;
                    final near = !over && ratio >= 0.8;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(b.category)),
                            Text(
                              '${_rupee.format(spent)} / '
                              '${_rupee.format(b.monthlyLimit)}',
                              style: TextStyle(
                                color: over
                                    ? scheme.error
                                    : near
                                        ? Colors.orange.shade700
                                        : null,
                                fontWeight:
                                    over || near ? FontWeight.w600 : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: ratio,
                          color: over
                              ? scheme.error
                              : near
                                  ? Colors.orange.shade700
                                  : scheme.primary,
                        ),
                      ],
                    );
                  }),
                ),
          ],
        ),
      ),
    );
  }
}

/// Subscriptions and other regular charges found in the history.
class _RecurringCard extends StatelessWidget {
  final List<Recurring> items;
  const _RecurringCard({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final monthly = items.fold<double>(
        0,
        (sum, r) =>
            sum + (r.cadence == 'monthly' ? r.typicalAmount : 0));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recurring payments',
                style: Theme.of(context).textTheme.titleMedium),
            if (monthly > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${_rupee.format(monthly)} a month in monthly charges',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            for (final r in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.autorenew, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${r.merchant} · ${r.cadence}',
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text(_rupee.format(r.typicalAmount),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
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
