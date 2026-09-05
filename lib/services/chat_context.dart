import '../data/db.dart';
import '../data/providers.dart' show DerivedAccount;
import '../models/models.dart';
import 'insights.dart';

/// Builds the briefing the chat model is given: a compact, plain-text
/// summary of the same data the Transactions, Dashboard, Accounts and Food
/// tabs are built from.
///
/// Everything here is derived from the local database. Raw SMS bodies are
/// deliberately left out — they carry reference numbers, one-time links and
/// unrelated personal messages, none of which the model needs to answer a
/// question about spending.
class ChatContext {
  /// How many recent transactions are listed individually. Older activity
  /// is still represented by the monthly and category totals.
  static const recentTransactionCount = 80;

  /// How many days of the food log are listed day by day.
  static const foodDays = 14;

  static String build({
    required List<Transaction> transactions,
    required List<Budget> budgets,
    required List<FoodEntry> food,
    required List<DerivedAccount> accounts,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final b = StringBuffer();

    b.writeln(_role);
    b.writeln();
    b.writeln('Today is ${_date(today)}.');
    b.writeln();

    _accounts(b, accounts);
    _thisMonth(b, transactions, today);
    _months(b, transactions, today);
    _budgets(b, budgets, transactions, today);
    _recurring(b, transactions);
    _recent(b, transactions);
    _food(b, food, today);

    return b.toString().trimRight();
  }

  static const _role = '''
You are the assistant inside an expense and food tracking app used by one
person in India. Amounts are Indian rupees; write them as Rs 1,234.

Everything you know about this person is in the DATA section below. It is
their own data from their own phone. Answer from it, do arithmetic on it
when asked, and be concrete: name merchants, categories, months and
figures. Keep answers short and direct - a couple of sentences or a short
list, not an essay - and expand only when asked.

Write plain text. The app shows your reply as-is, so do not use markdown:
no asterisks for emphasis, no hash headings, no tables. For a list, put
each item on its own line starting with "- ".

If the data does not cover a question, say exactly what is missing rather
than guessing. Transactions come from parsed bank SMS, so figures can be
incomplete: an account whose bank does not send alerts will not appear, and
cash spending is never captured. Say so when it matters to the answer.
Categories the person has not set yet show as Uncategorized.

Food entries are self-reported, and calorie figures are estimates. Give
general observations about eating patterns; do not diagnose, prescribe a
diet, or give medical advice.''';

  static void _accounts(StringBuffer b, List<DerivedAccount> accounts) {
    b.writeln('== DATA: ACCOUNTS ==');
    if (accounts.isEmpty) {
      b.writeln('No accounts detected yet.');
      b.writeln();
      return;
    }
    for (final a in accounts) {
      final parts = <String>[
        a.title,
        if (a.tail != null) 'ending ${a.tail}',
        _kind(a.kind),
        '${a.transactions.length} transactions',
        if (a.balance != null)
          'balance ${_money(a.balance!)} as of ${_date(a.balanceAsOf!)}',
      ];
      b.writeln('- ${parts.join(', ')}');
    }
    b.writeln();
  }

  static void _thisMonth(
      StringBuffer b, List<Transaction> all, DateTime today) {
    final month = DateTime(today.year, today.month);
    final current = _inMonth(all, month);
    b.writeln('== DATA: THIS MONTH (${_monthName(month)}) ==');
    if (current.isEmpty) {
      b.writeln('Nothing recorded this month yet.');
      b.writeln();
      return;
    }

    final spent = _spend(current);
    final received = current
        .where((t) => t.type == TxnType.credit)
        .fold(0.0, (s, t) => s + t.amount);
    b.writeln('Spent ${_money(spent)} across '
        '${current.where((t) => t.type == TxnType.debit).length} debits.');
    b.writeln('Received ${_money(received)}.');
    b.writeln('Net ${_money(received - spent)}.');

    final cats = Insights.byCategory(current).entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    if (cats.isNotEmpty) {
      b.writeln('By category:');
      for (final c in cats) {
        final share = spent > 0 ? (c.value / spent * 100).round() : 0;
        b.writeln('  ${c.key}: ${_money(c.value)} ($share%)');
      }
    }
    b.writeln();
  }

  static void _months(StringBuffer b, List<Transaction> all, DateTime today) {
    final totals = <String>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(today.year, today.month - i);
      totals.add('${_monthName(m)} ${_money(_spend(_inMonth(all, m)))}');
    }
    b.writeln('== DATA: SPEND BY MONTH (last 6) ==');
    b.writeln(totals.join(' | '));
    b.writeln();
  }

  static void _budgets(StringBuffer b, List<Budget> budgets,
      List<Transaction> all, DateTime today) {
    if (budgets.isEmpty) return;
    final current = _inMonth(all, DateTime(today.year, today.month));
    final byCategory = Insights.byCategory(current);
    b.writeln('== DATA: BUDGETS (this month) ==');
    for (final budget in budgets) {
      final used = byCategory[budget.category] ?? 0;
      final pct = budget.monthlyLimit > 0
          ? (used / budget.monthlyLimit * 100).round()
          : 0;
      b.writeln('- ${budget.category}: ${_money(used)} of '
          '${_money(budget.monthlyLimit)} ($pct%)');
    }
    b.writeln();
  }

  static void _recurring(StringBuffer b, List<Transaction> all) {
    final found = Insights.recurring(all);
    if (found.isEmpty) return;
    b.writeln('== DATA: LIKELY RECURRING PAYMENTS ==');
    for (final r in found.take(12)) {
      b.writeln('- ${r.merchant}: about ${_money(r.typicalAmount)} '
          '${r.cadence}, ${r.occurrences} times, last ${_date(r.lastSeen)}');
    }
    b.writeln();
  }

  static void _recent(StringBuffer b, List<Transaction> all) {
    b.writeln('== DATA: RECENT TRANSACTIONS (newest first) ==');
    if (all.isEmpty) {
      b.writeln('None recorded yet.');
      b.writeln();
      return;
    }
    b.writeln('date | in/out | amount | merchant | category | account');
    for (final t in all.take(recentTransactionCount)) {
      final account = [
        ?t.bank,
        if (t.accountTail != null) 'x${t.accountTail}',
        if (t.accountKind == AccountKind.creditCard) 'credit card',
      ].join(' ');
      b.writeln([
        _date(t.occurredAt),
        t.type == TxnType.debit ? 'out' : 'in',
        _money(t.amount),
        t.merchant ?? '?',
        t.category ?? 'Uncategorized',
        account.isEmpty ? '?' : account,
      ].join(' | '));
    }
    if (all.length > recentTransactionCount) {
      b.writeln('(${all.length - recentTransactionCount} older transactions '
          'not listed individually; the monthly totals above include them.)');
    }
    b.writeln();
  }

  static void _food(StringBuffer b, List<FoodEntry> food, DateTime today) {
    b.writeln('== DATA: FOOD LOG ==');
    if (food.isEmpty) {
      b.writeln('Nothing logged yet.');
      return;
    }

    final start = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: foodDays - 1));
    b.writeln('Daily totals for the last $foodDays days '
        '(calories, then protein/carbs/fat in grams; blank days omitted):');
    for (var i = 0; i < foodDays; i++) {
      final day = start.add(Duration(days: i));
      final entries = food
          .where((e) =>
              e.eatenAt.year == day.year &&
              e.eatenAt.month == day.month &&
              e.eatenAt.day == day.day)
          .toList();
      if (entries.isEmpty) continue;
      final kcal = entries.fold(
          0.0, (s, e) => s + (e.calories ?? 0) * e.servings);
      final p = _macro(entries, (e) => e.protein);
      final c = _macro(entries, (e) => e.carbs);
      final f = _macro(entries, (e) => e.fat);
      final unknown = entries.where((e) => e.calories == null).length;
      b.writeln('  ${_date(day)}: ${kcal.round()} kcal, '
          'P${p.round()} C${c.round()} F${f.round()}, '
          '${entries.length} items'
          '${unknown > 0 ? ' ($unknown without calories, so the day is a lower bound)' : ''}');
    }

    b.writeln('Items logged in the last 3 days:');
    final since = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 2));
    var listed = 0;
    for (final e in food) {
      if (e.eatenAt.isBefore(since)) continue;
      final kcal = (e.calories ?? 0) * e.servings;
      b.writeln('  ${_date(e.eatenAt)} ${e.meal.label}: ${e.name}'
          '${e.servings == 1 ? '' : ' x${_trim(e.servings)}'}'
          '${kcal > 0 ? ', ${kcal.round()} kcal' : ''}');
      listed++;
      if (listed >= 60) break;
    }
    if (listed == 0) b.writeln('  (nothing in the last 3 days)');

    final counts = <String, int>{};
    final monthAgo = today.subtract(const Duration(days: 30));
    for (final e in food) {
      if (e.eatenAt.isBefore(monthAgo)) continue;
      counts[e.name] = (counts[e.name] ?? 0) + 1;
    }
    if (counts.isNotEmpty) {
      final top = counts.entries.toList()
        ..sort((x, y) => y.value.compareTo(x.value));
      b.writeln('Most eaten in the last 30 days: '
          '${top.take(10).map((e) => '${e.key} (${e.value}x)').join(', ')}');
    }
  }

  // ---- formatting helpers ----

  static List<Transaction> _inMonth(List<Transaction> all, DateTime month) =>
      all
          .where((t) =>
              t.occurredAt.year == month.year &&
              t.occurredAt.month == month.month)
          .toList();

  static double _spend(Iterable<Transaction> txns) => txns
      .where((t) =>
          t.type == TxnType.debit && t.category != Categories.creditCardBill)
      .fold(0.0, (sum, t) => sum + t.amount);

  static double _macro(
          Iterable<FoodEntry> entries, double? Function(FoodEntry) pick) =>
      entries.fold(0.0, (sum, e) => sum + (pick(e) ?? 0) * e.servings);

  static String _kind(AccountKind kind) => switch (kind) {
        AccountKind.bank => 'bank account',
        AccountKind.creditCard => 'credit card',
        AccountKind.wallet => 'wallet',
        AccountKind.unknown => 'unknown type',
      };

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_monthNames[d.month - 1]} ${d.year}';

  static String _monthName(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

  /// Rupees with thousands separators, in the Indian grouping the person is
  /// used to seeing everywhere else in the app.
  static String _money(double v) {
    final negative = v < 0;
    final digits = v.abs().round().toString();
    String grouped;
    if (digits.length <= 3) {
      grouped = digits;
    } else {
      final last3 = digits.substring(digits.length - 3);
      var rest = digits.substring(0, digits.length - 3);
      final chunks = <String>[];
      while (rest.length > 2) {
        chunks.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) chunks.insert(0, rest);
      grouped = '${chunks.join(',')},$last3';
    }
    return '${negative ? '-' : ''}Rs $grouped';
  }

  static String _trim(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
