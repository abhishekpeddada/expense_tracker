/// Core domain types shared across the app.
library;

enum TxnType { debit, credit }

/// Which meal a food entry belongs to.
enum Meal { breakfast, lunch, dinner, snack }

extension MealLabel on Meal {
  String get label => switch (this) {
        Meal.breakfast => 'Breakfast',
        Meal.lunch => 'Lunch',
        Meal.dinner => 'Dinner',
        Meal.snack => 'Snack',
      };

  /// The meal most likely being eaten at this hour, used to preselect one.
  static Meal forHour(int hour) {
    if (hour < 11) return Meal.breakfast;
    if (hour < 16) return Meal.lunch;
    if (hour < 21) return Meal.dinner;
    return Meal.snack;
  }
}

/// Where the money moved from/to.
enum AccountKind { bank, creditCard, wallet, unknown }

/// Spending categories. `creditCardBill` is special-cased: paying a credit
/// card bill from a bank account should not double-count as spending.
class Categories {
  static const food = 'Food & Dining';
  static const groceries = 'Groceries';
  static const travel = 'Travel';
  static const shopping = 'Shopping';
  static const bills = 'Bills & Utilities';
  static const entertainment = 'Entertainment';
  static const health = 'Health';
  static const education = 'Education';
  static const rent = 'Rent';
  static const creditCardBill = 'Credit Card Bill';
  static const transfer = 'Transfer';
  static const salary = 'Salary';
  static const refund = 'Refund';
  static const other = 'Other';

  static const all = [
    food,
    groceries,
    travel,
    shopping,
    bills,
    entertainment,
    health,
    education,
    rent,
    creditCardBill,
    transfer,
    salary,
    refund,
    other,
  ];
}
