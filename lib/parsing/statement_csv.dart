import 'package:csv/csv.dart';

import '../models/models.dart';

class StatementRow {
  final DateTime date;
  final String description;
  final double amount;
  final TxnType type;
  final double? balance;

  const StatementRow({
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    this.balance,
  });

  @override
  String toString() =>
      'StatementRow($date, $type, $amount, "$description", bal: $balance)';
}

/// Best-effort parser for bank statement CSV exports (HDFC/SBI/ICICI/Axis
/// style). Bank CSVs differ wildly — preamble junk, different column names,
/// separate debit/credit columns vs a signed amount column — so this hunts
/// for the header row and maps columns by keyword.
class StatementCsvParser {
  static List<StatementRow> parse(String content) {
    final rows =
        const CsvDecoder().convert(content.replaceAll('\r\n', '\n'));

    final headerIdx = _findHeader(rows);
    if (headerIdx == null) return const [];
    final header = [
      for (final c in rows[headerIdx]) c.toString().trim().toLowerCase()
    ];

    int? find(List<String> keys, {List<String> avoid = const []}) {
      for (var i = 0; i < header.length; i++) {
        final h = header[i];
        if (avoid.any(h.contains)) continue;
        if (keys.any(h.contains)) return i;
      }
      return null;
    }

    final dateIdx = find(['date']);
    final descIdx = find(
        ['narration', 'description', 'particulars', 'remarks', 'details']);
    final debitIdx =
        find(['withdrawal', 'debit', 'dr amount'], avoid: ['card']);
    final creditIdx =
        find(['deposit', 'credit'], avoid: ['card', 'credit card']);
    final amountIdx = find(['amount'], avoid: ['withdrawal', 'deposit']);
    final typeIdx = find(['dr/cr', 'cr/dr', 'type']);
    final balanceIdx = find(['balance', 'bal']);
    if (dateIdx == null) return const [];

    final out = <StatementRow>[];
    for (var r = headerIdx + 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.length <= dateIdx) continue;
      final date = _parseDate(row[dateIdx].toString().trim());
      if (date == null) continue;

      final desc = (descIdx != null && row.length > descIdx)
          ? row[descIdx].toString().trim()
          : '';

      double? amount;
      TxnType? type;
      final debit =
          debitIdx != null && row.length > debitIdx ? _num(row[debitIdx]) : null;
      final credit = creditIdx != null && row.length > creditIdx
          ? _num(row[creditIdx])
          : null;
      if (debit != null && debit > 0) {
        amount = debit;
        type = TxnType.debit;
      } else if (credit != null && credit > 0) {
        amount = credit;
        type = TxnType.credit;
      } else if (amountIdx != null && row.length > amountIdx) {
        final a = _num(row[amountIdx]);
        if (a != null && a != 0) {
          final t = typeIdx != null && row.length > typeIdx
              ? row[typeIdx].toString().trim().toLowerCase()
              : '';
          if (t.startsWith('cr')) {
            type = TxnType.credit;
          } else if (t.startsWith('dr')) {
            type = TxnType.debit;
          } else {
            type = a < 0 ? TxnType.debit : TxnType.credit;
          }
          amount = a.abs();
        }
      }
      if (amount == null || type == null) continue;

      final balance = balanceIdx != null && row.length > balanceIdx
          ? _num(row[balanceIdx])
          : null;

      out.add(StatementRow(
        date: date,
        description: desc,
        amount: amount,
        type: type,
        balance: balance,
      ));
    }
    return out;
  }

  static int? _findHeader(List<List<dynamic>> rows) {
    for (var i = 0; i < rows.length; i++) {
      final cells = [
        for (final c in rows[i]) c.toString().trim().toLowerCase()
      ];
      final hasDate = cells.any((c) => c.contains('date'));
      final hasMoney = cells.any((c) =>
          c.contains('debit') ||
          c.contains('withdrawal') ||
          c.contains('credit') ||
          c.contains('deposit') ||
          c.contains('amount'));
      if (hasDate && hasMoney) return i;
    }
    return null;
  }

  static double? _num(dynamic cell) {
    final s = cell
        .toString()
        .replaceAll(',', '')
        .replaceAll('₹', '')
        .replaceAll('"', '')
        .replaceAll('INR', '')
        .trim();
    if (s.isEmpty || s == '-') return null;
    return double.tryParse(s);
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime? _parseDate(String s) {
    if (s.isEmpty) return null;
    // yyyy-MM-dd
    var m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (m != null) {
      return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
          int.parse(m.group(3)!));
    }
    // dd/MM/yyyy, dd-MM-yyyy, dd/MM/yy
    m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$').firstMatch(s);
    if (m != null) {
      var year = int.parse(m.group(3)!);
      if (year < 100) year += 2000;
      final month = int.parse(m.group(2)!);
      final day = int.parse(m.group(1)!);
      if (month > 12 || day > 31) return null;
      return DateTime(year, month, day);
    }
    // dd MMM yyyy / dd-MMM-yy / 01 Aug 2026
    m = RegExp(r'^(\d{1,2})[ /-]([A-Za-z]{3,})[ /-](\d{2,4})$').firstMatch(s);
    if (m != null) {
      final month = _months[m.group(2)!.toLowerCase().substring(0, 3)];
      if (month == null) return null;
      var year = int.parse(m.group(3)!);
      if (year < 100) year += 2000;
      return DateTime(year, month, int.parse(m.group(1)!));
    }
    return null;
  }
}
