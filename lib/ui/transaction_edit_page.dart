import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';

/// Add a transaction by hand, or edit one the parser got wrong.
class TransactionEditPage extends ConsumerStatefulWidget {
  /// Null when adding a new transaction.
  final Transaction? existing;
  const TransactionEditPage({super.key, this.existing});

  @override
  ConsumerState<TransactionEditPage> createState() =>
      _TransactionEditPageState();
}

class _TransactionEditPageState extends ConsumerState<TransactionEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _merchant;
  late final TextEditingController _bank;
  late final TextEditingController _tail;
  late final TextEditingController _note;

  late TxnType _type;
  late AccountKind _kind;
  late DateTime _when;
  String? _category;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(
        text: e == null ? '' : e.amount.toStringAsFixed(2));
    _merchant = TextEditingController(text: e?.merchant ?? '');
    _bank = TextEditingController(text: e?.bank ?? '');
    _tail = TextEditingController(text: e?.accountTail ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _type = e?.type ?? TxnType.debit;
    _kind = e?.accountKind ?? AccountKind.bank;
    _when = e?.occurredAt ?? DateTime.now();
    _category = e?.category;
  }

  @override
  void dispose() {
    for (final c in [_amount, _merchant, _bank, _tail, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = ref.read(dbProvider);
    final amount = double.parse(_amount.text.trim());
    final navigator = Navigator.of(context);

    if (_isEdit) {
      await db.updateTransaction(
        widget.existing!.id,
        amount: amount,
        type: _type,
        accountKind: _kind,
        merchant: _text(_merchant),
        bank: _text(_bank),
        accountTail: _text(_tail),
        category: _category,
        note: _text(_note),
        occurredAt: _when,
      );
    } else {
      await db.insertTransaction(TransactionsCompanion.insert(
        amount: amount,
        type: _type,
        accountKind: _kind,
        merchant: Value(_text(_merchant)),
        bank: Value(_text(_bank)),
        accountTail: Value(_text(_tail)),
        category: Value(_category),
        note: Value(_text(_note)),
        occurredAt: _when,
      ));
    }

    // Teach the merchant-to-category rule from a manual edit too.
    if (_category != null) {
      await ref.read(categorizerProvider).learn(_text(_merchant), _category!);
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit transaction' : 'Add transaction'),
        actions: [
          TextButton(onPressed: _save, child: const Text('SAVE')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _amount,
              autofocus: !_isEdit,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null || n <= 0) return 'Enter an amount';
                return null;
              },
            ),
            const SizedBox(height: 16),
            SegmentedButton<TxnType>(
              segments: const [
                ButtonSegment(value: TxnType.debit, label: Text('Spent')),
                ButtonSegment(value: TxnType.credit, label: Text('Received')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<AccountKind>(
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: 'Paid from',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                    value: AccountKind.bank, child: Text('Bank account')),
                DropdownMenuItem(
                    value: AccountKind.creditCard, child: Text('Credit card')),
                DropdownMenuItem(
                    value: AccountKind.wallet, child: Text('Wallet or cash')),
                DropdownMenuItem(
                    value: AccountKind.unknown, child: Text('Unspecified')),
              ],
              onChanged: (v) => setState(() => _kind = v ?? AccountKind.bank),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _merchant,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Merchant or description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('None yet')),
                for (final c in Categories.all)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _bank,
                    decoration: const InputDecoration(
                      labelText: 'Bank',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _tail,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Last 4',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(DateFormat('d MMM yyyy, h:mm a').format(_when)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _when,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (d != null) {
                  setState(() => _when =
                      DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
                }
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
