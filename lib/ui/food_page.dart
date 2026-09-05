import 'package:drift/drift.dart' show Value;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';
import 'food_entry_page.dart';

final _dayFmt = DateFormat('EEE, d MMM');
final _timeFmt = DateFormat('h:mm a');

/// Total calories for a set of entries, counting servings. Entries with no
/// calorie figure contribute nothing rather than breaking the total.
double _calories(Iterable<FoodEntry> entries) => entries.fold(
    0.0, (sum, e) => sum + (e.calories ?? 0) * e.servings);

/// The Food tab: what was eaten on a given day, with a running dashboard
/// built from the log.
class FoodPage extends ConsumerStatefulWidget {
  const FoodPage({super.key});

  @override
  ConsumerState<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends ConsumerState<FoodPage> {
  DateTime _day = DateUtils.dateOnly(DateTime.now());

  bool get _isToday => DateUtils.isSameDay(_day, DateTime.now());

  @override
  Widget build(BuildContext context) {
    final dayEntries =
        ref.watch(foodForDayProvider(_day)).valueOrNull ?? const <FoodEntry>[];
    final allEntries =
        ref.watch(foodEntriesProvider).valueOrNull ?? const <FoodEntry>[];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FoodEntryPage(day: _day)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add food'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _DayPicker(
            day: _day,
            onChanged: (d) => setState(() => _day = d),
          ),
          const SizedBox(height: 12),
          _DaySummary(entries: dayEntries, isToday: _isToday),
          const SizedBox(height: 20),
          if (allEntries.isNotEmpty) ...[
            _QuickAdd(recent: allEntries, day: _day),
            const SizedBox(height: 20),
          ],
          _MealSections(entries: dayEntries),
          const SizedBox(height: 20),
          _WeekChart(all: allEntries, endingOn: _day),
          const SizedBox(height: 20),
          _TopFoods(all: allEntries),
        ],
      ),
    );
  }
}

class _DayPicker extends StatelessWidget {
  final DateTime day;
  final ValueChanged<DateTime> onChanged;
  const _DayPicker({required this.day, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final isToday = DateUtils.isSameDay(day, today);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () =>
              onChanged(day.subtract(const Duration(days: 1))),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: day,
                firstDate: DateTime(2020),
                lastDate: today,
              );
              if (picked != null) onChanged(DateUtils.dateOnly(picked));
            },
            child: Center(
              child: Text(
                isToday ? 'Today' : _dayFmt.format(day),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          // Logging ahead of today is not useful.
          onPressed: isToday
              ? null
              : () => onChanged(day.add(const Duration(days: 1))),
        ),
      ],
    );
  }
}

class _DaySummary extends StatelessWidget {
  final List<FoodEntry> entries;
  final bool isToday;
  const _DaySummary({required this.entries, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _calories(entries);
    final withoutCalories =
        entries.where((e) => e.calories == null).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  total > 0 ? total.round().toString() : '—',
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(color: scheme.primary,
                          fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('kcal',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${entries.length}',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text('item${entries.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  isToday
                      ? 'Nothing logged yet today. Tap Add food to start.'
                      : 'Nothing was logged on this day.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else if (withoutCalories > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '$withoutCalories item'
                  '${withoutCalories == 1 ? '' : 's'} logged without '
                  'calories, so the total is a lower bound.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One-tap re-logging of foods eaten before, which is most of what daily
/// logging actually is.
class _QuickAdd extends ConsumerWidget {
  final List<FoodEntry> recent;
  final DateTime day;
  const _QuickAdd({required this.recent, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Most recently eaten distinct foods.
    final seen = <String>{};
    final picks = <FoodEntry>[];
    for (final e in recent) {
      if (seen.add(e.name.toLowerCase())) picks.add(e);
      if (picks.length == 10) break;
    }
    if (picks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Log again', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final e in picks)
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(e.name),
                onPressed: () async {
                  final now = DateTime.now();
                  await ref.read(dbProvider).insertFoodEntry(
                        FoodEntriesCompanion.insert(
                          name: e.name,
                          meal: MealLabel.forHour(now.hour),
                          calories: Value(e.calories),
                          servings: Value(e.servings),
                          eatenAt: DateTime(day.year, day.month, day.day,
                              now.hour, now.minute),
                        ),
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Logged ${e.name}')),
                    );
                  }
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _MealSections extends ConsumerWidget {
  final List<FoodEntry> entries;
  const _MealSections({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final meal in Meal.values)
          Builder(builder: (context) {
            final forMeal = entries.where((e) => e.meal == meal).toList();
            if (forMeal.isEmpty) return const SizedBox.shrink();
            final kcal = _calories(forMeal);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Row(
                    children: [
                      Text(meal.label,
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      if (kcal > 0)
                        Text('${kcal.round()} kcal',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                for (final e in forMeal) _FoodTile(entry: e),
              ],
            );
          }),
      ],
    );
  }
}

class _FoodTile extends ConsumerWidget {
  final FoodEntry entry;
  const _FoodTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kcal = (entry.calories ?? 0) * entry.servings;
    final servingsLabel =
        entry.servings == 1 ? null : '${_trim(entry.servings)} servings';

    return Dismissible(
      key: ValueKey('food-${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade700,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) async {
        await ref.read(dbProvider).deleteFoodEntry(entry.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Removed ${entry.name}')),
          );
        }
      },
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(entry.name),
        subtitle: Text([
          _timeFmt.format(entry.eatenAt),
          ?servingsLabel,
          ?entry.note,
        ].join(' · ')),
        trailing: Text(
          kcal > 0 ? '${kcal.round()} kcal' : '—',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FoodEntryPage(existing: entry),
          ),
        ),
      ),
    );
  }

  static String _trim(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Calories per day over the week ending on the selected day.
class _WeekChart extends StatelessWidget {
  final List<FoodEntry> all;
  final DateTime endingOn;
  const _WeekChart({required this.all, required this.endingOn});

  @override
  Widget build(BuildContext context) {
    final days = [
      for (var i = 6; i >= 0; i--)
        DateUtils.dateOnly(endingOn.subtract(Duration(days: i))),
    ];
    final totals = [
      for (final d in days)
        _calories(all.where((e) => DateUtils.isSameDay(e.eatenAt, d))),
    ];
    final maxY = totals.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxY <= 0) return const SizedBox.shrink();

    final logged = totals.where((v) => v > 0).toList();
    final average = logged.isEmpty
        ? 0.0
        : logged.reduce((a, b) => a + b) / logged.length;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last 7 days',
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Averaging ${average.round()} kcal on days with entries',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
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
                          if (i < 0 || i >= days.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('E').format(days[i]).substring(0, 1),
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
                        '${rod.toY.round()} kcal',
                        TextStyle(color: scheme.onInverseSurface),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < totals.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: totals[i],
                          color: i == totals.length - 1
                              ? scheme.primary
                              : scheme.primary.withValues(alpha: 0.4),
                          width: 16,
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

/// What gets eaten most often, over the last 30 days.
class _TopFoods extends StatelessWidget {
  final List<FoodEntry> all;
  const _TopFoods({required this.all});

  @override
  Widget build(BuildContext context) {
    final since = DateTime.now().subtract(const Duration(days: 30));
    final counts = <String, int>{};
    for (final e in all) {
      if (e.eatenAt.isBefore(since)) continue;
      counts[e.name] = (counts[e.name] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();

    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Eaten most, last 30 days',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final e in top.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                        child:
                            Text(e.key, overflow: TextOverflow.ellipsis)),
                    Text('${e.value}x',
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
