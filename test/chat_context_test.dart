import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:expense_tracker/data/db.dart';
import 'package:expense_tracker/data/providers.dart';
import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/services/chat_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 15, 12);

  Transaction txn({
    required double amount,
    TxnType type = TxnType.debit,
    String? merchant,
    String? category,
    String? bank,
    String? tail,
    AccountKind kind = AccountKind.bank,
    DateTime? at,
    String? rawSms,
  }) =>
      Transaction(
        id: amount.round() + (at?.day ?? 0) * 1000,
        amount: amount,
        type: type,
        accountKind: kind,
        accountTail: tail,
        merchant: merchant,
        bank: bank,
        category: category,
        rawSms: rawSms,
        source: 'sms',
        occurredAt: at ?? now,
        createdAt: at ?? now,
        synced: false,
      );

  FoodEntry food({
    required String name,
    required DateTime at,
    double? calories,
    double servings = 1,
    double? protein,
    Meal meal = Meal.lunch,
  }) =>
      FoodEntry(
        id: at.millisecondsSinceEpoch ~/ 1000,
        name: name,
        meal: meal,
        calories: calories,
        servings: servings,
        protein: protein,
        eatenAt: at,
        createdAt: at,
      );

  String build({
    List<Transaction> transactions = const [],
    List<Budget> budgets = const [],
    List<FoodEntry> foodEntries = const [],
    List<DerivedAccount> accounts = const [],
  }) =>
      ChatContext.build(
        transactions: transactions,
        budgets: budgets,
        food: foodEntries,
        accounts: accounts,
        now: now,
      );

  group('briefing content', () {
    test('states today so relative questions can be answered', () {
      expect(build(), contains('Today is 15 Sep 2026'));
    });

    test('summarises the current month with category shares', () {
      final out = build(transactions: [
        txn(amount: 600, merchant: 'Swiggy', category: Categories.food),
        txn(amount: 400, merchant: 'Uber', category: Categories.travel),
        txn(amount: 5000, type: TxnType.credit, category: Categories.salary),
      ]);
      expect(out, contains('Spent Rs 1,000'));
      expect(out, contains('Received Rs 5,000'));
      expect(out, contains('Net Rs 4,000'));
      expect(out, contains('Food & Dining: Rs 600 (60%)'));
      expect(out, contains('Travel: Rs 400 (40%)'));
    });

    test('groups rupees the Indian way', () {
      final out = build(transactions: [
        txn(amount: 1250000, merchant: 'Car', category: Categories.shopping),
      ]);
      expect(out, contains('Rs 12,50,000'));
    });

    test('a credit card bill payment is not counted as spending', () {
      final out = build(transactions: [
        txn(amount: 900, merchant: 'Shop', category: Categories.shopping),
        txn(
            amount: 20000,
            merchant: 'HDFC Card',
            category: Categories.creditCardBill),
      ]);
      expect(out, contains('Spent Rs 900'));
    });

    test('lists uncategorized transactions as such', () {
      final out = build(transactions: [txn(amount: 100, merchant: 'Kirana')]);
      expect(out, contains('Uncategorized'));
    });

    test('reports budgets against this month', () {
      final out = build(
        transactions: [
          txn(amount: 4000, merchant: 'Swiggy', category: Categories.food),
        ],
        budgets: [
          Budget(id: 1, category: Categories.food, monthlyLimit: 5000),
        ],
      );
      expect(out, contains('Food & Dining: Rs 4,000 of Rs 5,000 (80%)'));
    });

    test('omits the budget section when none are set', () {
      expect(build(), isNot(contains('BUDGETS')));
    });

    test('describes accounts including balance', () {
      final out = build(accounts: [
        DerivedAccount(
          bank: 'HDFC',
          tail: '5942',
          kind: AccountKind.creditCard,
          transactions: [txn(amount: 100)],
          balance: 45000,
          balanceAsOf: DateTime(2026, 9, 14),
        ),
      ]);
      expect(out, contains('HDFC'));
      expect(out, contains('ending 5942'));
      expect(out, contains('credit card'));
      expect(out, contains('balance Rs 45,000 as of 14 Sep 2026'));
    });

    test('spans six months of totals', () {
      final out = build(transactions: [
        txn(amount: 300, category: Categories.food, at: DateTime(2026, 7, 3)),
      ]);
      expect(out, contains('Apr 2026'));
      expect(out, contains('Jul 2026 Rs 300'));
      expect(out, contains('Sep 2026'));
    });
  });

  group('recent transactions', () {
    test('lists them newest first with account detail', () {
      final out = build(transactions: [
        txn(
          amount: 250,
          merchant: 'Swiggy',
          category: Categories.food,
          bank: 'ICICI',
          tail: '1234',
          at: DateTime(2026, 9, 14),
        ),
      ]);
      expect(out, contains('14 Sep 2026 | out | Rs 250 | Swiggy | '
          'Food & Dining | ICICI x1234'));
    });

    test('caps the list and says how many were left out', () {
      final many = [
        for (var i = 0; i < 100; i++)
          txn(amount: 10, merchant: 'Shop $i', at: DateTime(2026, 9, 10)),
      ];
      final out = build(transactions: many);
      expect(out, contains('Shop 0'));
      expect(out, isNot(contains('Shop 90')));
      expect(out, contains('20 older transactions'));
    });

    test('never includes raw SMS text', () {
      final out = build(transactions: [
        txn(
          amount: 100,
          merchant: 'Shop',
          rawSms: 'Your OTP is 445566 do not share SECRETTOKEN',
        ),
      ]);
      expect(out, isNot(contains('SECRETTOKEN')));
      expect(out, isNot(contains('445566')));
    });
  });

  group('food log', () {
    test('gives daily totals with macros', () {
      final out = build(foodEntries: [
        food(
            name: 'Dosa',
            at: DateTime(2026, 9, 15, 8),
            calories: 133,
            servings: 2,
            protein: 3),
      ]);
      expect(out, contains('15 Sep 2026: 266 kcal'));
      expect(out, contains('P6'));
      expect(out, contains('Dosa'));
    });

    test('flags days that are only a lower bound', () {
      final out = build(foodEntries: [
        food(name: 'Home cooked', at: DateTime(2026, 9, 15, 13)),
      ]);
      expect(out, contains('lower bound'));
    });

    test('reports the most eaten foods of the month', () {
      final out = build(foodEntries: [
        for (var d = 1; d <= 5; d++)
          food(name: 'Idli', at: DateTime(2026, 9, d, 8), calories: 58),
      ]);
      expect(out, contains('Idli (5x)'));
    });

    test('says plainly when nothing is logged', () {
      expect(build(), contains('Nothing logged yet'));
    });
  });

  group('instructions to the model', () {
    test('sets the currency and the no-markdown rule', () {
      final out = build();
      expect(out, contains('Indian rupees'));
      expect(out, contains('do not use markdown'));
    });

    test('warns that SMS-derived data can be incomplete', () {
      expect(build(), contains('cash spending is never captured'));
    });

    test('rules out medical advice on the food side', () {
      expect(build(), contains('do not diagnose'));
    });
  });

  group('chat storage', () {
    late AppDb db;
    setUp(() => db = AppDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('keeps turns in order and clears on request', () async {
      await db.insertChatMessage(ChatMessagesCompanion.insert(
        role: 'user',
        content: 'Where is my money going?',
        createdAt: Value(DateTime(2026, 9, 15, 10)),
      ));
      await db.insertChatMessage(ChatMessagesCompanion.insert(
        role: 'assistant',
        content: 'Mostly food.',
        model: const Value('openai/gpt-4o-mini'),
        createdAt: Value(DateTime(2026, 9, 15, 10, 1)),
      ));

      final history = await db.chatHistory();
      expect(history.map((m) => m.role), ['user', 'assistant']);
      expect(history.last.model, 'openai/gpt-4o-mini');
      expect(history.last.isError, isFalse);

      await db.clearChat();
      expect(await db.chatHistory(), isEmpty);
    });

    test('an error turn is marked so it can be left out of history',
        () async {
      await db.insertChatMessage(ChatMessagesCompanion.insert(
        role: 'assistant',
        content: 'OpenRouter rejected the API key.',
        isError: const Value(true),
        createdAt: Value(DateTime(2026, 9, 15, 10)),
      ));
      expect((await db.chatHistory()).single.isError, isTrue);
    });
  });
}
