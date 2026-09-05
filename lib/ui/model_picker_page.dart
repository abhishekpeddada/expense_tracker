import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/openrouter.dart';
import '../services/settings_service.dart';

/// Every model OpenRouter offers, fetched once per visit. The list runs to
/// hundreds of entries, so it is searchable and filterable rather than a
/// plain dropdown.
final _modelsProvider = FutureProvider.autoDispose<List<OpenRouterModel>>(
  (ref) async {
    // The model list needs no key, so it loads before one is entered.
    final configured = ref.watch(openRouterProvider);
    if (configured != null) return configured.listModels();
    final anonymous =
        OpenRouterClient(apiKey: '', model: OpenRouterClient.defaultModel);
    ref.onDispose(anonymous.close);
    return anonymous.listModels();
  },
);

class ModelPickerPage extends ConsumerStatefulWidget {
  final String selected;
  const ModelPickerPage({super.key, required this.selected});

  @override
  ConsumerState<ModelPickerPage> createState() => _ModelPickerPageState();
}

class _ModelPickerPageState extends ConsumerState<ModelPickerPage> {
  final _search = TextEditingController();
  String _query = '';
  bool _freeOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<OpenRouterModel> _filter(List<OpenRouterModel> models) {
    final terms = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    return [
      for (final m in models)
        if ((!_freeOnly || m.isFree) &&
            terms.every((t) => m.searchable.contains(t)))
          m,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_modelsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a model')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search models',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FilterChip(
                label: const Text('Free models only'),
                selected: _freeOnly,
                onSelected: (v) => setState(() => _freeOnly = v),
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _Error(
                message: e is OpenRouterException
                    ? e.message
                    : 'Could not load the model list.',
                onRetry: () => ref.invalidate(_modelsProvider),
              ),
              data: (models) {
                final shown = _filter(models);
                if (shown.isEmpty) {
                  return const Center(child: Text('No models match.'));
                }
                return ListView.builder(
                  itemCount: shown.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          '${shown.length} of ${models.length} models',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    }
                    final m = shown[i - 1];
                    final isSelected = m.id == widget.selected;
                    return ListTile(
                      title: Text(m.name),
                      subtitle: Text(
                        [m.id, m.priceLabel, m.contextLabel]
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      selected: isSelected,
                      onTap: () => Navigator.pop(context, m.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Error extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Error({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
