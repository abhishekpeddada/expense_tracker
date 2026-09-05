import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:expense_tracker/data/db.dart';
import 'package:expense_tracker/models/models.dart';
import 'package:expense_tracker/nutrition/food_table.dart';
import 'package:expense_tracker/nutrition/nutrition.dart';
import 'package:expense_tracker/services/nutrition_lookup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FoodTable', () {
    test('search prefers names starting with the query', () {
      final hits = FoodTable.search('do');
      expect(hits.first.name, 'Dosa');
    });

    test('search also finds names containing the query', () {
      final names = FoodTable.search('biryani').map((f) => f.name);
      expect(names, contains('Chicken Biryani'));
      expect(names, contains('Veg Biryani'));
    });

    test('search is case insensitive and ignores padding', () {
      expect(FoodTable.search('  IDLI ').single.name, 'Idli');
    });

    test('empty query returns nothing', () {
      expect(FoodTable.search(''), isEmpty);
      expect(FoodTable.search('   '), isEmpty);
    });

    test('exact match finds a food regardless of case', () {
      expect(FoodTable.exact('chicken biryani')?.calories, 480);
      expect(FoodTable.exact('not a real food'), isNull);
    });
  });

  group('MealLabel.forHour', () {
    test('maps the hour to the likely meal', () {
      expect(MealLabel.forHour(8), Meal.breakfast);
      expect(MealLabel.forHour(13), Meal.lunch);
      expect(MealLabel.forHour(20), Meal.dinner);
      expect(MealLabel.forHour(23), Meal.snack);
    });
  });

  group('food log database', () {
    late AppDb db;
    setUp(() => db = AppDb.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<int> log(String name, DateTime at,
        {double? calories, double servings = 1, Meal meal = Meal.lunch}) {
      return db.insertFoodEntry(FoodEntriesCompanion.insert(
        name: name,
        meal: meal,
        calories: Value(calories),
        servings: Value(servings),
        eatenAt: at,
      ));
    }

    test('a day query returns only that day, in order', () async {
      final day = DateTime(2026, 9, 5);
      await log('Dinner item', DateTime(2026, 9, 5, 20), calories: 300);
      await log('Breakfast item', DateTime(2026, 9, 5, 8), calories: 100);
      await log('Yesterday', DateTime(2026, 9, 4, 12), calories: 500);

      final entries = await db.watchFoodForDay(day).first;
      expect(entries.map((e) => e.name), ['Breakfast item', 'Dinner item']);
    });

    test('servings multiply the logged calories', () async {
      final day = DateTime(2026, 9, 5);
      await log('Idli', DateTime(2026, 9, 5, 8), calories: 58, servings: 3);
      final entries = await db.watchFoodForDay(day).first;
      final total = entries.fold<double>(
          0, (sum, e) => sum + (e.calories ?? 0) * e.servings);
      expect(total, 174);
    });

    test('entries without calories are kept and count as zero', () async {
      final day = DateTime(2026, 9, 5);
      await log('Home cooked', DateTime(2026, 9, 5, 13));
      final entries = await db.watchFoodForDay(day).first;
      expect(entries.single.calories, isNull);
      final total = entries.fold<double>(
          0, (sum, e) => sum + (e.calories ?? 0) * e.servings);
      expect(total, 0);
    });

    test('an entry can be edited and deleted', () async {
      final day = DateTime(2026, 9, 5);
      final id = await log('Tea', DateTime(2026, 9, 5, 7), calories: 60);
      await db.updateFoodEntry(
        id,
        name: 'Black Coffee',
        meal: Meal.breakfast,
        calories: 5,
        servings: 2,
        note: 'no sugar',
        eatenAt: DateTime(2026, 9, 5, 7, 30),
      );
      var entries = await db.watchFoodForDay(day).first;
      expect(entries.single.name, 'Black Coffee');
      expect(entries.single.servings, 2);
      expect(entries.single.note, 'no sugar');

      await db.deleteFoodEntry(id);
      entries = await db.watchFoodForDay(day).first;
      expect(entries, isEmpty);
    });

    test('macros and their provenance survive a round trip', () async {
      final day = DateTime(2026, 9, 5);
      await db.insertFoodEntry(FoodEntriesCompanion.insert(
        name: 'Dosa',
        meal: Meal.breakfast,
        calories: const Value(133),
        servings: const Value(2),
        protein: const Value(2.7),
        carbs: const Value(25.6),
        fat: const Value(3.7),
        servingSize: const Value('1 plain dosa'),
        nutritionSource: const Value(NutritionEstimate.sourceAi),
        nutritionModel: const Value('openai/gpt-4o-mini'),
        eatenAt: DateTime(2026, 9, 5, 8),
      ));

      final e = (await db.watchFoodForDay(day).first).single;
      expect(e.protein, closeTo(2.7, 0.001));
      expect(e.carbs, closeTo(25.6, 0.001));
      expect(e.fat, closeTo(3.7, 0.001));
      expect(e.servingSize, '1 plain dosa');
      expect(e.nutritionSource, NutritionEstimate.sourceAi);
      expect(e.nutritionModel, 'openai/gpt-4o-mini');
    });

    test('editing can clear macros back to unknown', () async {
      final day = DateTime(2026, 9, 5);
      final id = await db.insertFoodEntry(FoodEntriesCompanion.insert(
        name: 'Dosa',
        meal: Meal.breakfast,
        calories: const Value(133),
        protein: const Value(2.7),
        eatenAt: DateTime(2026, 9, 5, 8),
      ));
      await db.updateFoodEntry(
        id,
        name: 'Dosa',
        meal: Meal.breakfast,
        calories: 133,
        servings: 1,
        eatenAt: DateTime(2026, 9, 5, 8),
      );
      final e = (await db.watchFoodForDay(day).first).single;
      expect(e.protein, isNull);
      expect(e.nutritionSource, isNull);
    });

    test('the same entry restored twice is detected', () async {
      final at = DateTime(2026, 9, 5, 8);
      await log('Idli', at, calories: 58);
      expect(await db.hasFoodEntry('Idli', at), isTrue);
      expect(await db.hasFoodEntry('Idli', DateTime(2026, 9, 5, 9)), isFalse);
      expect(await db.hasFoodEntry('Vada', at), isFalse);
    });
  });

  group('NutritionLookup without a key', () {
    final lookup = NutritionLookup(null);

    test('cannot ask a model', () {
      expect(lookup.canAskModel, isFalse);
    });

    test('still answers from the bundled list', () async {
      final e = await lookup.lookup('Idli');
      expect(e?.calories, 58);
      expect(e?.source, NutritionEstimate.sourceTable);
      expect(e?.hasMacros, isFalse);
    });

    test('returns nothing for a food the list does not know', () async {
      expect(await lookup.lookup('Ragi Mudde With Bassaru'), isNull);
      expect(await lookup.lookup('   '), isNull);
    });
  });
}
