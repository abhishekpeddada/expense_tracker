import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../nutrition/food_table.dart';

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
  late final TextEditingController _note;

  late Meal _meal;
  late DateTime _when;
  List<FoodSuggestion> _suggestions = const [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _calories = TextEditingController(
        text: e?.calories == null ? '' : e!.calories!.toStringAsFixed(0));
    _servings =
        TextEditingController(text: (e?.servings ?? 1).toStringAsFixed(
            (e?.servings ?? 1) % 1 == 0 ? 0 : 1));
    _note = TextEditingController(text: e?.note ?? '');

    final base = widget.day ?? DateTime.now();
    final now = DateTime.now();
    // Logging for an earlier day keeps the current time of day.
    _when = e?.eatenAt ??
        DateTime(base.year, base.month, base.day, now.hour, now.minute);
    _meal = e?.meal ?? MealLabel.forHour(_when.hour);
  }

  @override
  void dispose() {
    for (final c in [_name, _calories, _servings, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onNameChanged(String value) {
    setState(() => _suggestions = FoodTable.search(value));
    // Fill calories when the typed name is an exact known food and the
    // field has not been edited by hand.
    final match = FoodTable.exact(value);
    if (match != null && _calories.text.trim().isEmpty) {
      _calories.text = match.calories.toStringAsFixed(0);
    }
  }

  void _pick(FoodSuggestion s) {
    setState(() {
      _name.text = s.name;
      _calories.text = s.calories.toStringAsFixed(0);
      _suggestions = const [];
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = ref.read(dbProvider);
    final navigator = Navigator.of(context);

    final name = _name.text.trim();
    final calories = double.tryParse(_calories.text.trim());
    final servings = double.tryParse(_servings.text.trim()) ?? 1;
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();

    if (_isEdit) {
      await db.updateFoodEntry(
        widget.existing!.id,
        name: name,
        meal: _meal,
        calories: calories,
        servings: servings,
        note: note,
        eatenAt: _when,
      );
    } else {
      await db.insertFoodEntry(FoodEntriesCompanion.insert(
        name: name,
        meal: _meal,
        calories: Value(calories),
        servings: Value(servings),
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
              decoration: const InputDecoration(
                labelText: 'What did you eat?',
                hintText: 'Idli, Chicken Biryani, Tea...',
                border: OutlineInputBorder(),
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
                    onChanged: (_) => setState(() {}),
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
            if (total != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Total ${total.round()} kcal',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Calories are optional. Suggested values are rough estimates '
              'for a typical serving.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
