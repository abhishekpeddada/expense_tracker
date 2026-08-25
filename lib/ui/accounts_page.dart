import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../parsing/statement_csv.dart';
import 'transactions_page.dart' show TransactionTile;

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
final _dateFmt = DateFormat('d MMM, h:mm a');

/// Accounts derived from SMS + imported statements. No live bank link —
/// see README for why that needs the Account Aggregator framework.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final now = DateTime.now();

    return Scaffold(
      body: accounts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_outlined,
                        size: 56, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 12),
                    Text('No accounts yet',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Accounts appear automatically from bank SMS, or '
                      'import a bank statement CSV.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final a in accounts)
                  _AccountCard(account: a, now: now),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => importStatement(context, ref),
        icon: const Icon(Icons.upload_file),
        label: const Text('Import CSV'),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final DerivedAccount account;
  final DateTime now;
  const _AccountCard({required this.account, required this.now});

  @override
  Widget build(BuildContext context) {
    final a = account;
    final isCard = a.kind == AccountKind.creditCard;
    double monthSpend = 0;
    for (final t in a.transactions) {
      if (t.type == TxnType.debit &&
          t.category != Categories.creditCardBill &&
          t.occurredAt.year == now.year &&
          t.occurredAt.month == now.month) {
        monthSpend += t.amount;
      }
    }

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          child: Icon(isCard ? Icons.credit_card : Icons.account_balance),
        ),
        title: Text(
          '${a.title}${a.tail != null ? ' ••${a.tail}' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (a.balance != null)
              Text(
                '${isCard ? 'Avl limit' : 'Balance'}: '
                '${_rupee.format(a.balance)}'
                ' · as of ${_dateFmt.format(a.balanceAsOf!)}',
              ),
            Text(
                'This month: ${_rupee.format(monthSpend)} spent · '
                '${a.transactions.length} transactions'),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AccountDetailPage(account: a)),
        ),
      ),
    );
  }
}

class AccountDetailPage extends ConsumerWidget {
  final DerivedAccount account;
  const AccountDetailPage({super.key, required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-derive so the page stays live after categorize/delete.
    final live = ref.watch(accountsProvider).where((a) =>
        a.bank == account.bank &&
        a.tail == account.tail &&
        a.kind == account.kind);
    final a = live.isEmpty ? account : live.first;

    return Scaffold(
      appBar: AppBar(
        title: Text('${a.title}${a.tail != null ? ' ••${a.tail}' : ''}'),
      ),
      body: ListView(
        children: [
          if (a.balance != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${a.kind == AccountKind.creditCard ? 'Available limit' : 'Balance'}: '
                '${_rupee.format(a.balance)} (as of '
                '${_dateFmt.format(a.balanceAsOf!)})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          for (final t in a.transactions) TransactionTile(txn: t),
        ],
      ),
    );
  }
}

/// Picks a CSV statement, parses it, and imports rows the DB doesn't
/// already have. Asks which bank/last-4 the statement belongs to so the
/// rows land in the right derived account.
Future<void> importStatement(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['csv', 'txt'],
  );
  if (picked == null) return;
  final content =
      utf8.decode(await picked.readAsBytes(), allowMalformed: true);

  final rows = StatementCsvParser.parse(content);
  if (!context.mounted) return;
  if (rows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Could not find any transactions in that file. Export the '
            'statement as CSV from netbanking and try again.')));
    return;
  }

  final bankCtrl = TextEditingController();
  final tailCtrl = TextEditingController();
  final from = rows.map((r) => r.date).reduce((a, b) => a.isBefore(b) ? a : b);
  final to = rows.map((r) => r.date).reduce((a, b) => a.isAfter(b) ? a : b);
  final fmt = DateFormat('d MMM yyyy');

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Import statement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${rows.length} transactions found '
              '(${fmt.format(from)} – ${fmt.format(to)}).'),
          const SizedBox(height: 16),
          TextField(
            controller: bankCtrl,
            decoration: const InputDecoration(
              labelText: 'Bank name (e.g. HDFC Bank)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: tailCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Account last 4 digits (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import')),
      ],
    ),
  );
  if (confirmed != true) return;

  final db = ref.read(dbProvider);
  final bank = bankCtrl.text.trim().isEmpty ? null : bankCtrl.text.trim();
  final tail = tailCtrl.text.trim().isEmpty ? null : tailCtrl.text.trim();

  var imported = 0, skipped = 0;
  for (final r in rows) {
    final merchant = r.description.isEmpty ? null : r.description;
    if (await db.hasSimilarTransaction(r.date, r.amount, r.type, merchant)) {
      skipped++;
      continue;
    }
    await db.insertTransaction(TransactionsCompanion.insert(
      amount: r.amount,
      type: r.type,
      accountKind: AccountKind.bank,
      accountTail: Value(tail),
      merchant: Value(merchant),
      bank: Value(bank),
      balance: Value(r.balance),
      occurredAt: r.date,
    ));
    imported++;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Imported $imported transactions'
            '${skipped > 0 ? ' ($skipped already existed)' : ''}')));
  }
}
