import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nutrition/food_table.dart';
import '../nutrition/nutrition.dart';
import 'openrouter.dart';
import 'settings_service.dart';

/// Finds nutrition for a food name: the bundled reference list first (free
/// and instant), then the configured OpenRouter model for anything the list
/// does not know.
class NutritionLookup {
  NutritionLookup(this._client);

  final OpenRouterClient? _client;

  bool get canAskModel => _client != null;

  /// Answers already fetched this session, so re-typing or editing an entry
  /// does not spend another request.
  static final Map<String, NutritionEstimate> _cache = {};

  static String _cacheKey(String food, String? note, String model) =>
      '$model|${food.trim().toLowerCase()}|${note?.trim().toLowerCase() ?? ''}';

  /// The bundled list's figure for an exact name match, or null.
  NutritionEstimate? fromTable(String food) {
    final match = FoodTable.exact(food);
    if (match == null) return null;
    return NutritionEstimate(
      calories: match.calories,
      servingSize: match.serving,
      source: NutritionEstimate.sourceTable,
    );
  }

  /// Nutrition for one serving of [food]. Throws [OpenRouterException] when
  /// the model was asked and could not answer.
  ///
  /// [preferModel] asks the model even for a food the bundled list knows,
  /// which is what the estimate button does — the model also returns macros
  /// and a serving description, which the list does not have.
  Future<NutritionEstimate?> lookup(
    String food, {
    String? note,
    bool preferModel = false,
  }) async {
    final name = food.trim();
    if (name.isEmpty) return null;

    final client = _client;
    if (client == null) return fromTable(name);
    if (!preferModel) {
      final table = fromTable(name);
      if (table != null) return table;
    }

    final key = _cacheKey(name, note, client.model);
    final cached = _cache[key];
    if (cached != null) return cached;

    final estimate = await client.estimate(name, note: note);
    _cache[key] = estimate;
    return estimate;
  }
}

final nutritionLookupProvider = Provider<NutritionLookup>(
  (ref) => NutritionLookup(ref.watch(openRouterProvider)),
);
