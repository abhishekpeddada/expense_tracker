/// Nutrition figures for a single serving of a food.
library;

class NutritionEstimate {
  /// Calories in one serving.
  final double? calories;

  /// Grams per serving.
  final double? protein;
  final double? carbs;
  final double? fat;

  /// What one serving means, as described by the source ("1 cup", "2 idli").
  final String? servingSize;

  /// Where the numbers came from, stored with the entry for provenance.
  final String source;

  /// Model id, when [source] is [sourceAi].
  final String? model;

  /// Anything the source wanted to flag, e.g. an assumption it made.
  final String? note;

  const NutritionEstimate({
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.servingSize,
    required this.source,
    this.model,
    this.note,
  });

  /// Typed in by hand.
  static const sourceManual = 'manual';

  /// Prefilled from the bundled reference list.
  static const sourceTable = 'table';

  /// Estimated by a model through OpenRouter.
  static const sourceAi = 'ai';

  bool get isEmpty =>
      calories == null && protein == null && carbs == null && fat == null;

  bool get hasMacros => protein != null || carbs != null || fat != null;
}
