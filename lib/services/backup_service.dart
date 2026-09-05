import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db.dart';
import '../models/models.dart';

/// Backup format version. Bumped only if the shape below changes in a way
/// older builds could not read.
const _formatVersion = 2;

class RestoreResult {
  final int transactions;
  final int messages;
  final int food;
  final int skipped;
  const RestoreResult(
      this.transactions, this.messages, this.food, this.skipped);
}

/// Exports and restores everything the app stores, as a plain JSON file the
/// user can keep anywhere (Google Drive, email, another phone).
///
/// Settings are deliberately not included: the OpenRouter API key is a
/// credential and must not travel in a file that gets shared around.
///
/// This is deliberately independent of the SQLite file: a JSON snapshot
/// survives schema changes, a raw database copy does not.
class BackupService {
  BackupService(this._db);

  final AppDb _db;

  Future<Map<String, Object?>> _snapshot() async {
    final txns = await _db.select(_db.transactions).get();
    final msgs = await _db.select(_db.smsMessages).get();
    final food = await _db.select(_db.foodEntries).get();
    return {
      'formatVersion': _formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'transactions': [
        for (final t in txns)
          {
            'amount': t.amount,
            'type': t.type.name,
            'accountKind': t.accountKind.name,
            'accountTail': t.accountTail,
            'merchant': t.merchant,
            'bank': t.bank,
            'category': t.category,
            'note': t.note,
            'rawSms': t.rawSms,
            'smsSender': t.smsSender,
            'balance': t.balance,
            'occurredAt': t.occurredAt.toIso8601String(),
          },
      ],
      'messages': [
        for (final m in msgs)
          {
            'sender': m.sender,
            'body': m.body,
            'receivedAt': m.receivedAt.toIso8601String(),
            'isTransaction': m.isTransaction,
            'read': m.read,
            'outgoing': m.outgoing,
          },
      ],
      'food': [
        for (final f in food)
          {
            'name': f.name,
            'meal': f.meal.name,
            'calories': f.calories,
            'servings': f.servings,
            'protein': f.protein,
            'carbs': f.carbs,
            'fat': f.fat,
            'servingSize': f.servingSize,
            'nutritionSource': f.nutritionSource,
            'nutritionModel': f.nutritionModel,
            'note': f.note,
            'eatenAt': f.eatenAt.toIso8601String(),
          },
      ],
    };
  }

  /// Writes a backup file and opens the share sheet, so it can be saved to
  /// Google Drive, sent to another device, or stored anywhere else.
  Future<void> exportAndShare() async {
    final json = const JsonEncoder.withIndent('  ').convert(await _snapshot());
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 16)
        .replaceAll(RegExp(r'[:T]'), '-');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/expense-tracker-backup-$stamp.json');
    await file.writeAsString(json);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Expense Tracker backup',
        text: 'Expense Tracker backup — save this to Google Drive.',
      ),
    );
  }

  /// Exports transactions as CSV for a spreadsheet, rather than the JSON
  /// backup format which is meant for restoring into this app.
  Future<void> exportCsv() async {
    final txns = await (_db.select(_db.transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .get();

    String cell(Object? v) {
      final s = v?.toString() ?? '';
      return s.contains(RegExp(r'[",\n]'))
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    }

    final rows = <String>[
      'Date,Type,Amount,Merchant,Category,Bank,Account,Note',
      for (final t in txns)
        [
          t.occurredAt.toIso8601String(),
          t.type.name,
          t.amount.toStringAsFixed(2),
          cell(t.merchant),
          cell(t.category),
          cell(t.bank),
          cell(t.accountTail),
          cell(t.note),
        ].join(','),
    ];

    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 16)
        .replaceAll(RegExp(r'[:T]'), '-');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/expense-tracker-$stamp.csv');
    await file.writeAsString(rows.join('\n'));

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Expense Tracker transactions',
        text: 'Transactions exported from Expense Tracker.',
      ),
    );
  }

  /// Restores from a previously exported file. Existing data is kept;
  /// entries already present are skipped so restoring twice is harmless.
  Future<RestoreResult> importFromFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null) return const RestoreResult(0, 0, 0, 0);

    final raw = utf8.decode(await picked.readAsBytes(), allowMalformed: true);
    final data = jsonDecode(raw);
    if (data is! Map || data['formatVersion'] == null) {
      throw const FormatException('Not an Expense Tracker backup file.');
    }

    var txnCount = 0, msgCount = 0, foodCount = 0, skipped = 0;

    for (final e in (data['transactions'] as List? ?? [])) {
      final m = (e as Map).cast<String, Object?>();
      final occurredAt = DateTime.parse(m['occurredAt'] as String);
      final amount = (m['amount'] as num).toDouble();
      final type = TxnType.values.byName(m['type'] as String);
      final merchant = m['merchant'] as String?;
      if (await _db.hasSimilarTransaction(occurredAt, amount, type, merchant)) {
        skipped++;
        continue;
      }
      await _db.insertTransaction(TransactionsCompanion.insert(
        amount: amount,
        type: type,
        accountKind: AccountKind.values.byName(m['accountKind'] as String),
        accountTail: Value(m['accountTail'] as String?),
        merchant: Value(merchant),
        bank: Value(m['bank'] as String?),
        category: Value(m['category'] as String?),
        note: Value(m['note'] as String?),
        rawSms: Value(m['rawSms'] as String?),
        smsSender: Value(m['smsSender'] as String?),
        balance: Value((m['balance'] as num?)?.toDouble()),
        occurredAt: occurredAt,
      ));
      txnCount++;
    }

    for (final e in (data['messages'] as List? ?? [])) {
      final m = (e as Map).cast<String, Object?>();
      final receivedAt = DateTime.parse(m['receivedAt'] as String);
      final sender = m['sender'] as String;
      final body = m['body'] as String;
      if (await _db.hasMessage(sender, body, receivedAt)) {
        skipped++;
        continue;
      }
      await _db.insertMessage(SmsMessagesCompanion.insert(
        sender: sender,
        body: body,
        receivedAt: receivedAt,
        isTransaction: Value(m['isTransaction'] as bool? ?? false),
        read: Value(m['read'] as bool? ?? false),
        outgoing: Value(m['outgoing'] as bool? ?? false),
      ));
      msgCount++;
    }

    // Older backups (format 1) have no food section; the loop just no-ops.
    for (final e in (data['food'] as List? ?? [])) {
      final m = (e as Map).cast<String, Object?>();
      final eatenAt = DateTime.parse(m['eatenAt'] as String);
      final name = m['name'] as String;
      if (await _db.hasFoodEntry(name, eatenAt)) {
        skipped++;
        continue;
      }
      double? real(Object? v) => (v as num?)?.toDouble();
      await _db.insertFoodEntry(FoodEntriesCompanion.insert(
        name: name,
        meal: Meal.values.byName(m['meal'] as String),
        calories: Value(real(m['calories'])),
        servings: Value(real(m['servings']) ?? 1),
        protein: Value(real(m['protein'])),
        carbs: Value(real(m['carbs'])),
        fat: Value(real(m['fat'])),
        servingSize: Value(m['servingSize'] as String?),
        nutritionSource: Value(m['nutritionSource'] as String?),
        nutritionModel: Value(m['nutritionModel'] as String?),
        note: Value(m['note'] as String?),
        eatenAt: eatenAt,
      ));
      foodCount++;
    }

    return RestoreResult(txnCount, msgCount, foodCount, skipped);
  }
}
