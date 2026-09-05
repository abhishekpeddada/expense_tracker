/// Approximate calories for common foods, used only to prefill the field
/// when logging. Values are per typical single serving and are rounded
/// estimates, not a nutrition database — the user can always override.
library;

class FoodSuggestion {
  final String name;
  final double calories;
  final String serving;
  const FoodSuggestion(this.name, this.calories, this.serving);
}

class FoodTable {
  static const all = <FoodSuggestion>[
    // South Indian
    FoodSuggestion('Idli', 58, '1 piece'),
    FoodSuggestion('Dosa', 133, '1 plain'),
    FoodSuggestion('Masala Dosa', 250, '1'),
    FoodSuggestion('Vada', 97, '1 piece'),
    FoodSuggestion('Upma', 192, '1 cup'),
    FoodSuggestion('Pongal', 220, '1 cup'),
    FoodSuggestion('Uttapam', 175, '1'),
    FoodSuggestion('Sambar', 85, '1 cup'),
    FoodSuggestion('Rasam', 45, '1 cup'),
    FoodSuggestion('Coconut Chutney', 65, '2 tbsp'),
    FoodSuggestion('Curd Rice', 210, '1 cup'),
    FoodSuggestion('Lemon Rice', 250, '1 cup'),
    // North Indian
    FoodSuggestion('Roti', 104, '1'),
    FoodSuggestion('Chapati', 104, '1'),
    FoodSuggestion('Paratha', 210, '1'),
    FoodSuggestion('Naan', 262, '1'),
    FoodSuggestion('Poori', 150, '1'),
    FoodSuggestion('Dal', 130, '1 cup'),
    FoodSuggestion('Rajma', 210, '1 cup'),
    FoodSuggestion('Chole', 230, '1 cup'),
    FoodSuggestion('Paneer Butter Masala', 320, '1 cup'),
    FoodSuggestion('Palak Paneer', 270, '1 cup'),
    FoodSuggestion('Chicken Curry', 280, '1 cup'),
    FoodSuggestion('Butter Chicken', 380, '1 cup'),
    FoodSuggestion('Egg Curry', 240, '1 cup'),
    FoodSuggestion('Mixed Veg Curry', 150, '1 cup'),
    // Rice and biryani
    FoodSuggestion('Rice', 205, '1 cup cooked'),
    FoodSuggestion('Jeera Rice', 250, '1 cup'),
    FoodSuggestion('Veg Biryani', 350, '1 plate'),
    FoodSuggestion('Chicken Biryani', 480, '1 plate'),
    FoodSuggestion('Mutton Biryani', 550, '1 plate'),
    FoodSuggestion('Fried Rice', 330, '1 plate'),
    // Snacks and street food
    FoodSuggestion('Samosa', 260, '1'),
    FoodSuggestion('Pakora', 175, '4 pieces'),
    FoodSuggestion('Pav Bhaji', 400, '1 plate'),
    FoodSuggestion('Vada Pav', 290, '1'),
    FoodSuggestion('Pani Puri', 150, '6 pieces'),
    FoodSuggestion('Bhel Puri', 200, '1 plate'),
    FoodSuggestion('Poha', 180, '1 cup'),
    FoodSuggestion('Maggi', 310, '1 pack'),
    FoodSuggestion('Sandwich', 250, '1'),
    FoodSuggestion('Burger', 400, '1'),
    FoodSuggestion('Pizza Slice', 285, '1 slice'),
    FoodSuggestion('French Fries', 310, '1 medium'),
    FoodSuggestion('Momos', 210, '6 pieces'),
    FoodSuggestion('Noodles', 290, '1 plate'),
    // Eggs, meat, protein
    FoodSuggestion('Boiled Egg', 78, '1'),
    FoodSuggestion('Omelette', 155, '2 eggs'),
    FoodSuggestion('Grilled Chicken', 165, '100 g'),
    FoodSuggestion('Fish Curry', 220, '1 cup'),
    FoodSuggestion('Paneer', 265, '100 g'),
    FoodSuggestion('Curd', 98, '1 cup'),
    FoodSuggestion('Sprouts', 125, '1 cup'),
    // Drinks
    FoodSuggestion('Tea', 60, '1 cup with milk'),
    FoodSuggestion('Coffee', 70, '1 cup with milk'),
    FoodSuggestion('Black Coffee', 5, '1 cup'),
    FoodSuggestion('Milk', 150, '1 cup'),
    FoodSuggestion('Buttermilk', 40, '1 glass'),
    FoodSuggestion('Lassi', 260, '1 glass'),
    FoodSuggestion('Fruit Juice', 110, '1 glass'),
    FoodSuggestion('Soft Drink', 140, '330 ml'),
    // Fruit and sweets
    FoodSuggestion('Banana', 105, '1 medium'),
    FoodSuggestion('Apple', 95, '1 medium'),
    FoodSuggestion('Orange', 62, '1 medium'),
    FoodSuggestion('Mango', 200, '1 medium'),
    FoodSuggestion('Gulab Jamun', 150, '1 piece'),
    FoodSuggestion('Jalebi', 150, '1 piece'),
    FoodSuggestion('Ice Cream', 210, '1 scoop'),
    FoodSuggestion('Chocolate', 235, '1 bar'),
    FoodSuggestion('Biscuits', 140, '4 pieces'),
    FoodSuggestion('Almonds', 165, '25 g'),
  ];

  /// Foods whose name contains [query], best matches first: names that start
  /// with the query come before ones that merely contain it.
  static List<FoodSuggestion> search(String query, {int limit = 8}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final starts = <FoodSuggestion>[];
    final contains = <FoodSuggestion>[];
    for (final f in all) {
      final n = f.name.toLowerCase();
      if (n.startsWith(q)) {
        starts.add(f);
      } else if (n.contains(q)) {
        contains.add(f);
      }
    }
    return [...starts, ...contains].take(limit).toList();
  }

  /// Exact (case-insensitive) match, for filling calories on a known name.
  static FoodSuggestion? exact(String name) {
    final n = name.trim().toLowerCase();
    for (final f in all) {
      if (f.name.toLowerCase() == n) return f;
    }
    return null;
  }
}
