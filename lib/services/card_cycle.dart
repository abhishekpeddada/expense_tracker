import 'package:intl/intl.dart';

final _dayMonth = DateFormat('d MMM');
final _dayMonthYear = DateFormat('d MMM yyyy');

/// One credit card statement period.
class StatementCycle {
  /// First day of the period, at midnight.
  final DateTime start;

  /// The day the statement closes, at midnight. Spending on this day still
  /// belongs to this period — the statement is drawn at the end of it.
  final DateTime close;

  /// When the bill for this period has to be paid.
  final DateTime due;

  const StatementCycle({
    required this.start,
    required this.close,
    required this.due,
  });

  /// Exclusive upper bound, which is what comparing timestamps wants: a
  /// purchase at 11pm on the closing day is still inside the period.
  DateTime get endExclusive =>
      DateTime(close.year, close.month, close.day + 1);

  bool contains(DateTime when) =>
      !when.isBefore(start) && when.isBefore(endExclusive);

  /// True while the card can still be spent on for this period.
  bool get isOpen => contains(DateTime.now());

  /// "26 Sep – 25 Oct", with the year added when the period does not sit
  /// inside the current one.
  String get label {
    final sameYear = start.year == close.year;
    final thisYear = DateTime.now().year;
    final to = sameYear && close.year == thisYear ? _dayMonth : _dayMonthYear;
    return '${_dayMonth.format(start)} - ${to.format(close)}';
  }

  String get dueLabel => _dayMonthYear.format(due);
}

/// A credit card's billing cycle: when the statement closes, and when the
/// bill that follows it is paid.
///
/// A card spend lands on whichever statement is open when it happens, not
/// in whichever calendar month it happens, so a purchase on the 28th is
/// part of next month's bill. Counting card spending by calendar month
/// splits one bill across two months and makes neither add up.
class CardCycle {
  /// Day of the month the statement closes. Zero means the card is billed
  /// by calendar month, which is how it behaves until told otherwise.
  final int closingDay;

  /// Day of the month the bill is paid — the first one of those that falls
  /// after the statement closes.
  final int dueDay;

  const CardCycle({this.closingDay = 0, this.dueDay = 1});

  /// Highest day a cycle boundary can be set to. February is the reason:
  /// past this, a day would be clamped so often that it is clearer to call
  /// the card calendar-month billed instead.
  static const maxDay = 28;

  bool get isCalendarMonth => closingDay <= 0 || closingDay > maxDay;

  static int daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

  static int _clamp(int day, int year, int month) {
    final last = daysIn(year, month);
    return day < 1 ? 1 : (day > last ? last : day);
  }

  /// The period whose statement closes in [month].
  StatementCycle closingIn(DateTime month) {
    final y = month.year;
    final m = month.month;

    if (isCalendarMonth) {
      final close = DateTime(y, m, daysIn(y, m));
      return StatementCycle(
        start: DateTime(y, m, 1),
        close: close,
        due: _dueAfter(close),
      );
    }

    final close = DateTime(y, m, _clamp(closingDay, y, m));
    // DateTime normalises month 0 to December of the year before, so the
    // turn of the year needs no special case.
    final prev = DateTime(y, m - 1);
    final prevClose = _clamp(closingDay, prev.year, prev.month);
    return StatementCycle(
      start: DateTime(prev.year, prev.month, prevClose + 1),
      close: close,
      due: _dueAfter(close),
    );
  }

  /// The period [when] falls in.
  StatementCycle covering(DateTime when) {
    if (isCalendarMonth) {
      return closingIn(DateTime(when.year, when.month));
    }
    final closesThisMonth = _clamp(closingDay, when.year, when.month);
    // On the closing day itself the statement has not been drawn yet, so
    // that day still belongs to the period closing this month.
    final month = when.day <= closesThisMonth
        ? DateTime(when.year, when.month)
        : DateTime(when.year, when.month + 1);
    return closingIn(month);
  }

  /// The period open right now.
  StatementCycle get current => covering(DateTime.now());

  /// The most recent period that has closed, which is the one the next
  /// payment is for.
  StatementCycle get lastClosed {
    final open = current;
    return closingIn(DateTime(open.close.year, open.close.month - 1));
  }

  /// The first day the bill may be paid on or after [close].
  DateTime _dueAfter(DateTime close) {
    final same = DateTime(
        close.year, close.month, _clamp(dueDay, close.year, close.month));
    if (same.isAfter(close)) return same;
    final next = DateTime(close.year, close.month + 1);
    return DateTime(
        next.year, next.month, _clamp(dueDay, next.year, next.month));
  }
}
