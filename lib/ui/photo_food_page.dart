import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../models/models.dart';
import '../nutrition/nutrition.dart';
import '../services/nutrition_lookup.dart';
import '../services/openrouter.dart';
import '../services/settings_service.dart';
import 'settings_page.dart';

/// Photograph a plate and log what is on it.
///
/// A plate is usually several foods, so the model is asked to break it down
/// and the result is reviewed here before anything is written: portions
/// judged from a photo are guesses, and the person eating knows better.
class PhotoFoodPage extends ConsumerStatefulWidget {
  final ImageSource source;

  /// Day being viewed on the Food tab, so entries land on that date.
  final DateTime? day;

  const PhotoFoodPage({super.key, required this.source, this.day});

  @override
  ConsumerState<PhotoFoodPage> createState() => _PhotoFoodPageState();
}

class _PhotoFoodPageState extends ConsumerState<PhotoFoodPage> {
  Uint8List? _photo;
  bool _busy = true;
  String? _error;
  List<_Item> _items = [];

  late Meal _meal;
  late DateTime _when;
  final _hint = TextEditingController();

  @override
  void initState() {
    super.initState();
    final base = widget.day ?? DateTime.now();
    final now = DateTime.now();
    _when = DateTime(base.year, base.month, base.day, now.hour, now.minute);
    _meal = MealLabel.forHour(_when.hour);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickAndAnalyse());
  }

  @override
  void dispose() {
    _hint.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAndAnalyse() async {
    // Downscaled before it ever leaves the device: a vision model reads a
    // plate fine at this size, and a full-resolution phone photo would cost
    // several times as much to send.
    final picked = await ImagePicker().pickImage(
      source: widget.source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (!mounted) return;
    if (picked == null) {
      Navigator.pop(context);
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _photo = bytes);
    await _analyse();
  }

  Future<void> _analyse() async {
    final photo = _photo;
    if (photo == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    List<NutritionEstimate>? found;
    String? error;
    try {
      found = await ref.read(nutritionLookupProvider).fromPhoto(
            photo,
            note: _hint.text.trim().isEmpty ? null : _hint.text.trim(),
          );
    } on OpenRouterException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not read the photo: $e';
    }
    if (!mounted) return;

    for (final item in _items) {
      item.dispose();
    }
    setState(() {
      _busy = false;
      _error = error;
      _items = [for (final e in found ?? const <NutritionEstimate>[]) _Item(e)];
    });
  }

  Future<void> _save() async {
    final chosen = _items.where((i) => i.selected).toList();
    if (chosen.isEmpty) return;
    final db = ref.read(dbProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    for (final item in chosen) {
      await db.insertFoodEntry(FoodEntriesCompanion.insert(
        name: item.name.text.trim(),
        meal: _meal,
        calories: Value(double.tryParse(item.calories.text.trim())),
        servings: Value(double.tryParse(item.servings.text.trim()) ?? 1),
        protein: Value(item.estimate.protein),
        carbs: Value(item.estimate.carbs),
        fat: Value(item.estimate.fat),
        servingSize: Value(item.estimate.servingSize),
        nutritionSource: const Value(NutritionEstimate.sourcePhoto),
        nutritionModel: Value(item.estimate.model),
        eatenAt: _when,
      ));
    }
    messenger.showSnackBar(SnackBar(
      content: Text('Logged ${chosen.length} '
          'item${chosen.length == 1 ? '' : 's'}'),
    ));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _items.where((i) => i.selected).toList();
    final total = selected.fold<double>(
      0,
      (sum, i) =>
          sum +
          (double.tryParse(i.calories.text.trim()) ?? 0) *
              (double.tryParse(i.servings.text.trim()) ?? 1),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log from photo'),
        actions: [
          if (_photo != null && !_busy)
            IconButton(
              tooltip: 'Analyse again',
              icon: const Icon(Icons.refresh),
              onPressed: _analyse,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _photo!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 16),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Working out what is on the plate...'),
                ],
              ),
            )
          else if (_error != null)
            _ErrorBlock(message: _error!, onRetry: _analyse)
          else ...[
            Text('Found ${_items.length} '
                'item${_items.length == 1 ? '' : 's'}. '
                'Untick anything that is not yours and correct the portions '
                'before logging.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            for (final item in _items)
              _ItemCard(
                item: item,
                onChanged: () => setState(() {}),
              ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _hint,
            decoration: const InputDecoration(
              labelText: 'Anything the photo does not show',
              hintText: 'Cooked in ghee, half of it was shared, ...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _analyse(),
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(DateFormat('d MMM yyyy, h:mm a').format(_when)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _pickWhen,
          ),
          Text(
            'Portions judged from a photo are rough. Everything here can be '
            'edited afterwards by tapping the entry on the Food tab.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: selected.isEmpty ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(selected.isEmpty
                      ? 'Nothing selected'
                      : 'Log ${selected.length} '
                          'item${selected.length == 1 ? '' : 's'}'
                          '${total > 0 ? ' · ${total.round()} kcal' : ''}'),
                ),
              ),
            ),
    );
  }

  Future<void> _pickWhen() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    setState(() {
      _when = DateTime(d.year, d.month, d.day, t?.hour ?? _when.hour,
          t?.minute ?? _when.minute);
    });
  }
}

/// One detected food, with the fields the person can correct before it is
/// logged. Macros ride along unedited; the entry can be opened afterwards.
class _Item {
  final NutritionEstimate estimate;
  final TextEditingController name;
  final TextEditingController calories;
  final TextEditingController servings;
  bool selected = true;

  _Item(this.estimate)
      : name = TextEditingController(text: estimate.name ?? ''),
        calories = TextEditingController(
            text: estimate.calories == null
                ? ''
                : estimate.calories!.round().toString()),
        servings = TextEditingController(text: '1');

  void dispose() {
    name.dispose();
    calories.dispose();
    servings.dispose();
  }
}

class _ItemCard extends StatelessWidget {
  final _Item item;
  final VoidCallback onChanged;
  const _ItemCard({required this.item, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final e = item.estimate;
    final macros = [
      if (e.protein != null) 'P ${e.protein!.round()}g',
      if (e.carbs != null) 'C ${e.carbs!.round()}g',
      if (e.fat != null) 'F ${e.fat!.round()}g',
    ].join('  ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: item.selected,
                  onChanged: (v) {
                    item.selected = v ?? false;
                    onChanged();
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: item.name,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: item.calories,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Calories',
                        suffixText: 'kcal',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: item.servings,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Servings',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                ],
              ),
            ),
            if (e.servingSize != null || macros.isNotEmpty || e.note != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    [
                      if (e.servingSize != null) 'Seen as ${e.servingSize}',
                      if (macros.isNotEmpty) macros,
                      ?e.note,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBlock extends ConsumerWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acceptsImages = ref.watch(settingsProvider).modelAcceptsImages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        if (acceptsImages == false)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'The model you picked cannot read images. Choose one marked '
              'with a camera in Settings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
              child: const Text('Settings'),
            ),
          ],
        ),
      ],
    );
  }
}
