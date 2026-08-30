import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';

final _rupee =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const <Budget>[];
    final byCategory = {for (final b in budgets) b.category: b};

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Set a monthly cap for any category. The dashboard shows how '
              'much is left, and you get a notification at 80% and again '
              'when a cap is passed.',
            ),
          ),
          const Divider(height: 1),
          for (final c in Categories.all)
            ListTile(
              title: Text(c),
              subtitle: byCategory[c] == null
                  ? const Text('No budget')
                  : Text('${_rupee.format(byCategory[c]!.monthlyLimit)} '
                      'per month'),
              trailing: byCategory[c] == null
                  ? const Icon(Icons.add)
                  : IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          ref.read(dbProvider).deleteBudget(c),
                    ),
              onTap: () => _edit(context, ref, c, byCategory[c]?.monthlyLimit),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, String category, double? current) async {
    final ctrl = TextEditingController(
        text: current == null ? '' : current.toStringAsFixed(0));
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Monthly limit',
            prefixText: '₹ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(ctrl.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null && value > 0) {
      await ref.read(dbProvider).setBudget(category, value);
    }
  }
}
