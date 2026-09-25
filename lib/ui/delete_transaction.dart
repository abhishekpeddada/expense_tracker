import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

/// Asks before removing a transaction, naming what is about to go.
///
/// A swipe is easy to do by accident, and a parsed transaction cannot be
/// recovered from the SMS once it is gone, so the question is worth asking
/// even though an undo follows it.
Future<bool> confirmDeleteTransaction(
    BuildContext context, Transaction txn) async {
  final what = [
    _rupee.format(txn.amount),
    if (txn.merchant != null) 'at ${txn.merchant}',
  ].join(' ');

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete this transaction?'),
      content: Text(
        '$what on ${DateFormat('d MMM yyyy').format(txn.occurredAt)} '
        'will be removed from your totals.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Deletes the transaction and offers an undo for a few seconds.
///
/// The removed row is held in memory rather than re-derived, so undo puts
/// back exactly what was there - category, note and all - under its
/// original id.
Future<void> deleteTransactionWithUndo(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  Transaction txn,
) async {
  final db = ref.read(dbProvider);
  final removed = await db.deleteTransactionReturning(txn.id);
  if (removed == null) return;

  final label = txn.type == TxnType.debit ? 'Spend' : 'Credit';
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$label of ${_rupee.format(removed.amount)} deleted'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => db.restoreTransaction(removed),
        ),
      ),
    );
}

/// Confirm, then delete with an undo. Answers whether it went ahead.
Future<bool> confirmAndDeleteTransaction(
  BuildContext context,
  WidgetRef ref,
  Transaction txn,
) async {
  if (!await confirmDeleteTransaction(context, txn)) return false;
  if (!context.mounted) return false;
  await deleteTransactionWithUndo(ScaffoldMessenger.of(context), ref, txn);
  return true;
}
