import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import '../models/models.dart';

/// Warns once when a category budget crosses 80%, and once when it is
/// passed. State is kept per category per month so a single overspend does
/// not notify on every app resume.
class BudgetAlerts {
  BudgetAlerts(this._db);

  final AppDb _db;
  static const _channel = MethodChannel('expense_tracker/sms');

  Future<void> check() async {
    final prefs = await SharedPreferences.getInstance();
    final budgets = await _db.allBudgets();
    if (budgets.isEmpty) return;

    final now = DateTime.now();
    final txns = await _db.watchTransactions().first;
    final spend = <String, double>{};
    for (final t in txns) {
      if (t.type != TxnType.debit) continue;
      if (t.category == null || t.category == Categories.creditCardBill) {
        continue;
      }
      if (t.occurredAt.year != now.year || t.occurredAt.month != now.month) {
        continue;
      }
      spend[t.category!] = (spend[t.category!] ?? 0) + t.amount;
    }

    final period = '${now.year}-${now.month}';
    for (final b in budgets) {
      if (b.monthlyLimit <= 0) continue;
      final spent = spend[b.category] ?? 0;
      final ratio = spent / b.monthlyLimit;
      final stage = ratio >= 1.0 ? 2 : (ratio >= 0.8 ? 1 : 0);
      if (stage == 0) continue;

      final key = 'budgetAlert|$period|${b.category}';
      if ((prefs.getInt(key) ?? 0) >= stage) continue;

      await _notify(
        title: stage == 2
            ? '${b.category} budget passed'
            : '${b.category} budget almost used',
        body: stage == 2
            ? 'Spent ₹${spent.toStringAsFixed(0)} of '
                '₹${b.monthlyLimit.toStringAsFixed(0)} this month.'
            : '${(ratio * 100).round()}% used — '
                '₹${(b.monthlyLimit - spent).toStringAsFixed(0)} left.',
      );
      await prefs.setInt(key, stage);
    }
  }

  Future<void> _notify({required String title, required String body}) async {
    try {
      await _channel
          .invokeMethod('postBudgetAlert', {'title': title, 'body': body});
    } on MissingPluginException {
      // ignore off-Android
    }
  }
}
