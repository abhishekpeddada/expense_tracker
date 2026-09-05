import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../nutrition/food_table.dart';
import '../nutrition/nutrition.dart';
import '../services/nutrition_lookup.dart';
import '../services/openrouter.dart';
import '../services/settings_service.dart';
import 'settings_page.dart';

/// Log something eaten, or edit an entry already logged.
class FoodEntryPage extends ConsumerStatefulWidget {
  final FoodEntry? existing;

  /// Day being viewed, so a new entry lands on that date rather than today.
  final DateTime? day;

  const FoodEntryPage({super.key, this.existing, this.day});

  @override
  ConsumerState<FoodEntryPage> createState() => _FoodEntryPageState();
}

class _FoodEntryPageState extends ConsumerState<FoodEntryPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _calories;
  late final TextEditingController _servings;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late final TextEditingController _note;

  late Meal _meal;
  late DateTime _when;
  List<FoodSuggestion> _suggestions = const [];

  /// How the current numbers were arrived at, kept with the entry.
  String? _source;
  String? _model;
  String? _servingSize;
  String? _estimateNote;

  Timer? _debounce;
  bool _estimating = false;
  String? _estimateError;

  /// Name the last estimate was for, so idling on the same text does not
  /// fire a second request.
  String? _lastEstimatedFor;

  bool get _isEdit => widget.existing != null;

  /// Typing over the calories the model filled in means the user owns the
  /// number now; automatic lookups stop overwriting it.
  bool _caloriesEditedByHand = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _calories = TextEditingController(text: _fmt(e?.calories));
    _servings = TextEditingController(
        text: (e?.servings ?? 1).toStringAsFixed(
            (e?.servings ?? 1) % 1 == 0 ? 0 : 1));
    _protein = TextEditingController(text: _fmt(e?.protein));
    _carbs = TextEditingController(text: _fmt(e?.carbs));
    _fat = TextEditingController(text: _fmt(e?.fat));
    _note = TextEditingController(text: e?.note ?? '');

    _source = e?.nutritionSource;
    _model = e?.nutritionModel;
    _servingSize = e?.servingSize;
    _lastEstimatedFor = e?.name;
    _caloriesEditedByHand = e?.calories != null &&
        e?.nutritionSource == NutritionEstimate.sourceManual;

    final base = widget.day ?? DateTime.now();
    final now = DateTime.now();
    // Logging for an earlier day keeps the current time of day.
    _when = e?.eatenAt ??
        DateTime(base.year, base.month, base.day, now.hour, now.minute);
    _meal = e?.meal ?? MealLabel.forHour(_when.hour);
  }

  static String _fmt(double? v) {
    if (v == null) return '';
    return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [
      _name,
      _calories,
      _servings,
      _protein,
      _carbs,
      _fat,
      _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onNameChanged(String value) {
    setState(() {
      _suggestions = FoodTable.search(value);
      _estimateError = null;
    });

    // Instant, free prefill from the bundled list while anything better is
    // still being fetched.
    final match = FoodTable.exact(value);
    if (match != null && !_caloriesEditedByHand && _calories.text.trim().isEmpty) {
      setState(() {
        _calories.text = match.calories.toStringAsFixed(0);
        _servingSize = match.serving;
        _source = NutritionEstimate.sourceTable;
        _model = null;
      });
    }

    _debounce?.cancel();
    final settings = ref.read(settingsProvider);
    if (!settings.autoEstimate || !settings.hasKey) return;
    if (value.trim().length < 3) return;
    _debounce = Timer(
      const Duration(milliseconds: 900),
      () => _estimate(explicit: false),
    );
  }

  /// Asks for nutrition figures and fills the form in.
  ///
  /// An automatic lookup only fills blanks; tapping the estimate button
  /// replaces what is there, because that is what the user just asked for.
  Future<void> _estimate({required bool explicit}) async {
    final name = _name.text.trim();
    if (name.isEmpty || _estimating) return;
    if (!explicit && name == _lastEstimatedFor) return;

    final lookup = ref.read(nutritionLookupProvider);
    if (explicit && !lookup.canAskModel) {
      _promptForKey();
      return;
    }

    setState(() {
      _estimating = true;
      _estimateError = null;
    });

    NutritionEstimate? result;
    String? error;
    try {
      result = await lookup.lookup(
        name,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        preferModel: explicit,
      );
    } on OpenRouterException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Lookup failed: $e';
    }
    if (!mounted) return;

    setState(() {
      _estimating = false;
      _estimateError = error;
      _lastEstimatedFor = name;
      if (result == null) return;

      void fill(TextEditingController c, double? value, {bool force = false}) {
        if (value == null) return;
        if (!force && c.text.trim().isNotEmpty) return;
        c.text = _fmt(value);
      }

      fill(_calories, result.calories,
          force: explicit || !_caloriesEditedByHand);
      fill(_protein, result.protein, force: explicit);
      fill(_carbs, result.carbs, force: explicit);
      fill(_fat, result.fat, force: explicit);
      _servingSize = result.servingSize ?? _servingSize;
      _source = result.source;
      _model = result.model;
      _estimateNote = result.note;
      if (explicit) _caloriesEditedByHand = false;
    });
  }

  void _promptForKey() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Add an OpenRouter key to estimate nutrition.'),
        action: SnackBarAction(
          label: 'SETTINGS',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(FoodSuggestion s) async {
    setState(() {
      _name.text = s.name;
      _calories.text = s.calories.toStringAsFixed(0);
      _servingSize = s.serving;
      _source = NutritionEstimate.sourceTable;
      _model = null;
      _caloriesEditedByHand = false;
      _suggestions = const [];
    });
    FocusScope.of(context).unfocus();
    // The list has calories but no macros; the model fills the rest in.
    final settings = ref.read(settingsProvider);
    if (settings.autoEstimate && settings.hasKey) {
      await _estimate(explicit: true);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Typing fast and hitting save should still get an estimate, so the
    // pending debounce is honoured rather than dropped.
    _debounce?.cancel();
    final settings = ref.read(settingsProvider);
    if (_calories.text.trim().isEmpty &&
        settings.autoEstimate &&
        settings.hasKey) {
      await _estimate(explicit: false);
    }
    if (!mounted) return;

    final db = ref.read(dbProvider);
    final navigator = Navigator.of(context);

    final name = _name.text.trim();
    final calories = double.tryParse(_calories.text.trim());
    final servings = double.tryParse(_servings.text.trim()) ?? 1;
    final protein = double.tryParse(_protein.text.trim());
    final carbs = double.tryParse(_carbs.text.trim());
    final fat = double.tryParse(_fat.text.trim());
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final source = calories == null && protein == null
        ? null
        : (_caloriesEditedByHand
            ? NutritionEstimate.sourceManual
            : _source ?? NutritionEstimate.sourceManual);
    final model =
        source == NutritionEstimate.sourceAi ? _model : null;

    if (_isEdit) {
      await db.updateFoodEntry(
        widget.existing!.id,
        name: name,
        meal: _meal,
        calories: calories,
        servings: servings,
        protein: protein,
        carbs: carbs,
        fat: fat,
        servingSize: _servingSize,
        nutritionSource: source,
        nutritionModel: model,
        note: note,
        eatenAt: _when,
      );
    } else {
      await db.insertFoodEntry(FoodEntriesCompanion.insert(
        name: name,
        meal: _meal,
        calories: Value(calories),
        servings: Value(servings),
        protein: Value(protein),
        carbs: Value(carbs),
        fat: Value(fat),
        servingSize: Value(_servingSize),
        nutritionSource: Value(source),
        nutritionModel: Value(model),
        note: Value(note),
        eatenAt: _when,
      ));
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final perServing = double.tryParse(_calories.text.trim());
    final servings = double.tryParse(_servings.text.trim()) ?? 1;
    final total = perServing == null ? null : perServing * servings;
    final hasKey = ref.watch(settingsProvider).hasKey;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit food' : 'Add food'),
        actions: [TextButton(onPressed: _save, child: const Text('SAVE'))],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'What did you eat?',
                hintText: 'Idli, Chicken Biryani, Tea...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: hasKey
                      ? 'Estimate nutrition'
                      : 'Set up nutrition lookup',
                  icon: _estimating
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined),
                  onPressed:
                      _estimating ? null : () => _estimate(explicit: true),
                ),
              ),
              onChanged: _onNameChanged,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a food name' : null,
            ),
            if (_suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final s in _suggestions)
                      ActionChip(
                        label: Text('${s.name} · ${s.calories.round()} kcal'),
                        onPressed: () => _pick(s),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SegmentedButton<Meal>(
              segments: [
                for (final m in Meal.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {_meal},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _meal = s.first),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _calories,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Calories per serving',
                      suffixText: 'kcal',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {
                      _caloriesEditedByHand = true;
                      _source = NutritionEstimate.sourceManual;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _servings,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Servings',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _macroField(_protein, 'Protein')),
                const SizedBox(width: 8),
                Expanded(child: _macroField(_carbs, 'Carbs')),
                const SizedBox(width: 8),
                Expanded(child: _macroField(_fat, 'Fat')),
              ],
            ),
            if (total != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Total ${total.round()} kcal',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            const SizedBox(height: 8),
            _provenance(context),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(DateFormat('d MMM yyyy, h:mm a').format(_when)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _when,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (d == null || !context.mounted) return;
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(_when),
                );
                setState(() {
                  _when = DateTime(d.year, d.month, d.day,
                      t?.hour ?? _when.hour, t?.minute ?? _when.minute);
                });
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note',
                hintText: 'Half plate, extra ghee, ...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _macroField(TextEditingController c, String label) => TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'g',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setState(() {}),
      );

  /// One line saying where the numbers came from, or what went wrong.
  Widget _provenance(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final error = _estimateError;
    if (error != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline,
              size: 16, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              error,
              style: style?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      );
    }
    if (_estimating) {
      return Text('Estimating nutrition...', style: style);
    }

    final bits = <String>[
      if (_servingSize != null) 'Per ${_servingSize!}',
      switch (_source) {
        NutritionEstimate.sourceAi =>
          'estimated by ${_model ?? 'a model'}',
        NutritionEstimate.sourceTable => 'from the built-in list',
        NutritionEstimate.sourceManual => 'entered by hand',
        _ => '',
      },
      ?_estimateNote,
    ]..removeWhere((s) => s.isEmpty);

    if (bits.isEmpty) {
      return Text(
        ref.watch(settingsProvider).hasKey
            ? 'Calories are optional. Tap the star to estimate them.'
            : 'Calories are optional. Add an OpenRouter key in Settings to '
                'have them worked out automatically.',
        style: style,
      );
    }
    return Text('${bits.join(' · ')}. Estimates, not exact figures.',
        style: style);
  }
}
