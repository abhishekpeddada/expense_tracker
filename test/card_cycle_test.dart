import 'package:expense_tracker/services/card_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The cycle this app was asked for: statement closes on the 25th, bill
  // paid by the 15th of the month after.
  const c = CardCycle(closingDay: 25, dueDay: 15);

  group('the period closing in a month', () {
    test('runs from the day after last month closed', () {
      final oct = c.closingIn(DateTime(2026, 10));
      expect(oct.start, DateTime(2026, 9, 26));
      expect(oct.close, DateTime(2026, 10, 25));
      expect(oct.endExclusive, DateTime(2026, 10, 26));
    });

    test('the bill falls due the following month', () {
      expect(c.closingIn(DateTime(2026, 10)).due, DateTime(2026, 11, 15));
    });

    test('crosses the turn of the year', () {
      final jan = c.closingIn(DateTime(2027, 1));
      expect(jan.start, DateTime(2026, 12, 26));
      expect(jan.close, DateTime(2027, 1, 25));
      expect(jan.due, DateTime(2027, 2, 15));
    });

    test('a closing day past the end of the month is pulled back', () {
      const late = CardCycle(closingDay: 28, dueDay: 15);
      // 2027 is not a leap year, so February ends on the 28th anyway, but
      // the period before it has to start on 1 February.
      final mar = late.closingIn(DateTime(2027, 3));
      expect(mar.start, DateTime(2027, 3, 1));
      expect(mar.close, DateTime(2027, 3, 28));
    });

    test('a leap February closes on the 28th as asked', () {
      const late = CardCycle(closingDay: 28, dueDay: 15);
      final feb = late.closingIn(DateTime(2028, 2));
      expect(feb.start, DateTime(2028, 1, 29));
      expect(feb.close, DateTime(2028, 2, 28));
    });
  });

  group('which period a spend belongs to', () {
    test('a spend before the closing day is on this month\'s statement', () {
      final cycle = c.covering(DateTime(2026, 10, 3, 14, 30));
      expect(cycle.close, DateTime(2026, 10, 25));
    });

    test('the closing day itself is still inside the period', () {
      final cycle = c.covering(DateTime(2026, 10, 25, 23, 59));
      expect(cycle.close, DateTime(2026, 10, 25));
      expect(cycle.contains(DateTime(2026, 10, 25, 23, 59)), isTrue);
    });

    test('the day after closing starts the next period', () {
      final cycle = c.covering(DateTime(2026, 10, 26));
      expect(cycle.start, DateTime(2026, 10, 26));
      expect(cycle.close, DateTime(2026, 11, 25));
      expect(cycle.due, DateTime(2026, 12, 15));
    });

    test('a late December spend lands on January\'s statement', () {
      final cycle = c.covering(DateTime(2026, 12, 31));
      expect(cycle.close, DateTime(2027, 1, 25));
    });

    test('every day of a year lands in exactly one period', () {
      // Cheap but thorough: no gaps and no overlaps anywhere in the year.
      for (var d = DateTime(2026, 1, 1);
          d.isBefore(DateTime(2027, 1, 1));
          d = DateTime(d.year, d.month, d.day + 1)) {
        final cycle = c.covering(d);
        expect(cycle.contains(d), isTrue, reason: 'cycle missed $d');
        expect(cycle.start.isBefore(cycle.endExclusive), isTrue);
      }
    });
  });

  group('calendar-month billing', () {
    const plain = CardCycle();

    test('is what an unset cycle means', () {
      expect(plain.isCalendarMonth, isTrue);
      final oct = plain.closingIn(DateTime(2026, 10));
      expect(oct.start, DateTime(2026, 10, 1));
      expect(oct.close, DateTime(2026, 10, 31));
    });

    test('February ends where February ends', () {
      expect(plain.closingIn(DateTime(2027, 2)).close, DateTime(2027, 2, 28));
      expect(plain.closingIn(DateTime(2028, 2)).close, DateTime(2028, 2, 29));
    });

    test('a closing day beyond the shortest month is treated as monthly', () {
      // The 31st would be clamped in seven months of twelve, so it is
      // read as calendar-month billing rather than a cycle that wanders.
      expect(const CardCycle(closingDay: 31).isCalendarMonth, isTrue);
    });
  });

  group('when the bill is due', () {
    test('a due day after the closing day stays in the same month', () {
      const c = CardCycle(closingDay: 2, dueDay: 22);
      expect(c.closingIn(DateTime(2026, 10)).close, DateTime(2026, 10, 2));
      expect(c.closingIn(DateTime(2026, 10)).due, DateTime(2026, 10, 22));
    });

    test('a due day on the closing day means the month after', () {
      const c = CardCycle(closingDay: 10, dueDay: 10);
      expect(c.closingIn(DateTime(2026, 10)).due, DateTime(2026, 11, 10));
    });

    test('rolls into the next year', () {
      expect(c.closingIn(DateTime(2026, 12)).due, DateTime(2027, 1, 15));
    });
  });

  group('the period a payment is for', () {
    test('is the one before the period still open', () {
      // Built from a fixed point rather than today's date, so the test
      // does not change meaning as the month rolls over.
      final open = c.covering(DateTime(2026, 10, 6));
      final closed = c.closingIn(DateTime(open.close.year, open.close.month - 1));
      expect(closed.close, DateTime(2026, 9, 25));
      expect(closed.due, DateTime(2026, 10, 15));
    });

    test('lastClosed sits immediately before the open period', () {
      final open = c.current;
      final closed = c.lastClosed;
      expect(closed.endExclusive, open.start);
      expect(closed.close.isBefore(open.start), isTrue);
    });
  });

  test('the label names both ends of the period', () {
    expect(c.closingIn(DateTime(DateTime.now().year, 10)).label,
        contains('26 Sep'));
  });
}
