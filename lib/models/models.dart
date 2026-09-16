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

/// Spending categories.
///
/// Two of these move money between the user's own accounts rather than in
/// or out of their pocket, and are left out of every total — see
/// [internal].
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

  /// Money moved between two accounts the user owns. Nothing was spent or
  /// earned, so it counts towards neither.
  static const selfTransfer = 'Self Transfer';

  /// Money sent to somebody else, which is real spending.
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
    selfTransfer,
    transfer,
    salary,
    refund,
    other,
  ];

  /// Categories that shuffle money between the user's own accounts. Paying
  /// a credit card bill moves money to the card, where the original
  /// purchases were already counted; a self transfer moves money from one
  /// pocket to another. Counting either would inflate both what was spent
  /// and what came in.
  static const internal = {creditCardBill, selfTransfer};

  /// Spellings people actually type for the two internal categories.
  ///
  /// Categories are free text — the picker offers the list above but does
  /// not insist on it — so "Self transfer", "self transfers" and "Credit
  /// card bills" all reach the database as distinct strings. Comparing them
  /// literally meant a category that plainly says "this is my own money
  /// moving" still counted as spending.
  static const _internalAliases = {
    'self transfer',
    'selftransfer',
    'transfer to self',
    'own transfer',
    'own account transfer',
    'account transfer',
    'internal transfer',
    'credit card bill',
    'credit card payment',
    'card bill',
    'cc bill',
  };

  /// Case, spacing, punctuation and a trailing plural all removed, so
  /// "Credit card bills" and "Credit Card Bill" compare equal.
  static String _canonical(String category) {
    final stripped =
        category.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return stripped.endsWith('s')
        ? stripped.substring(0, stripped.length - 1)
        : stripped;
  }

  static final Set<String> _internalKeys = {
    for (final c in internal) _canonical(c),
    for (final c in _internalAliases) _canonical(c),
  };

  /// True when a transaction in this category should be left out of spend
  /// and income totals.
  static bool isInternal(String? category) =>
      category != null && _internalKeys.contains(_canonical(category));

  /// Compares a free-text category against one of the names above, ignoring
  /// case, spacing and a trailing plural.
  static bool same(String? category, String name) =>
      category != null && _canonical(category) == _canonical(name);
}
