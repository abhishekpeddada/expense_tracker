import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../nutrition/nutrition.dart';

/// A model offered by OpenRouter. Prices are USD per token, as the API
/// reports them; [pricePerMillion] is the friendlier form.
class OpenRouterModel {
  final String id;
  final String name;
  final String? description;
  final int? contextLength;
  final double? promptPrice;
  final double? completionPrice;

  /// True when the model accepts images as input, which is what photo
  /// logging needs. Text-only models reject the request outright.
  final bool acceptsImages;

  const OpenRouterModel({
    required this.id,
    required this.name,
    this.description,
    this.contextLength,
    this.promptPrice,
    this.completionPrice,
    this.acceptsImages = false,
  });

  bool get isFree => (promptPrice ?? 0) == 0 && (completionPrice ?? 0) == 0;

  /// Vendor part of the id ("anthropic" in "anthropic/claude-sonnet-4.5").
  String get vendor {
    final slash = id.indexOf('/');
    return slash <= 0 ? 'other' : id.substring(0, slash);
  }

  String get priceLabel {
    if (isFree) return 'Free';
    String per(double? v) =>
        v == null ? '?' : '\$${(v * 1000000).toStringAsFixed(2)}';
    return '${per(promptPrice)} in / ${per(completionPrice)} out per 1M';
  }

  String get contextLabel {
    final c = contextLength;
    if (c == null || c <= 0) return '';
    if (c >= 1000000) return '${(c / 1000000).toStringAsFixed(c % 1000000 == 0 ? 0 : 1)}M ctx';
    if (c >= 1000) return '${(c / 1000).round()}K ctx';
    return '$c ctx';
  }

  /// Text a search box matches against.
  String get searchable => '$id $name ${description ?? ''}'.toLowerCase();

  static OpenRouterModel fromJson(Map<String, Object?> m) {
    final pricing = (m['pricing'] as Map?)?.cast<String, Object?>() ?? {};
    double? price(Object? v) =>
        v == null ? null : double.tryParse(v.toString());
    final id = m['id'] as String? ?? '';
    final architecture =
        (m['architecture'] as Map?)?.cast<String, Object?>() ?? {};
    // Newer entries list input_modalities; older ones only carry the
    // combined modality string, so both are checked.
    final modalities = architecture['input_modalities'];
    final legacy = architecture['modality']?.toString() ?? '';
    final acceptsImages = modalities is List
        ? modalities.any((v) => v.toString() == 'image')
        : legacy.split('->').first.contains('image');

    return OpenRouterModel(
      id: id,
      acceptsImages: acceptsImages,
      name: (m['name'] as String?)?.trim().isNotEmpty == true
          ? m['name'] as String
          : id,
      description: m['description'] as String?,
      contextLength: (m['context_length'] as num?)?.toInt(),
      promptPrice: price(pricing['prompt']),
      completionPrice: price(pricing['completion']),
    );
  }
}

/// One message in a conversation sent to a model.
class ChatTurn {
  /// 'user' or 'assistant'.
  final String role;
  final String content;
  const ChatTurn(this.role, this.content);

  const ChatTurn.user(this.content) : role = 'user';
  const ChatTurn.assistant(this.content) : role = 'assistant';
}

class OpenRouterException implements Exception {
  final String message;

  /// True when the model hit its token budget before finishing. Reasoning
  /// models can burn the whole budget thinking and return nothing at all,
  /// so this is worth retrying with more room rather than reporting.
  final bool truncated;

  const OpenRouterException(this.message, {this.truncated = false});
  @override
  String toString() => message;
}

/// Talks to OpenRouter for the model list and for nutrition estimates.
///
/// The API key lives only in on-device preferences and is sent to
/// openrouter.ai and nowhere else. Only the food name, servings and any note
/// the user typed leave the device.
class OpenRouterClient {
  OpenRouterClient({required this.apiKey, required this.model, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _http;

  /// Releases the underlying connections. Safe to call more than once.
  void close() => _http.close();

  static const _base = 'https://openrouter.ai/api/v1';

  /// Default pick when the user has not chosen a model. Cheap and fast, and
  /// good enough for "roughly how many calories is this".
  static const defaultModel = 'openai/gpt-4o-mini';

  Map<String, String> get _headers => {
        // The model list is public, so an empty key must not send a bare
        // "Bearer " header that OpenRouter would reject.
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        // OpenRouter uses these for attribution on its dashboard.
        'HTTP-Referer': 'https://github.com/abhishekpeddada/expense_tracker',
        'X-Title': 'Expense Tracker',
      };

  /// Every model OpenRouter currently offers, sorted by id.
  Future<List<OpenRouterModel>> listModels() async {
    final res = await _get(Uri.parse('$_base/models'));
    return parseModels(res);
  }

  /// Confirms the key works, returning a short description of the account.
  Future<String> checkKey() async {
    final body = await _get(Uri.parse('$_base/key'));
    final data = (jsonDecode(body) as Map)['data'];
    if (data is! Map) return 'Key accepted.';
    final label = data['label'] as String?;
    final limit = data['limit'];
    final usage = data['usage'];
    final parts = <String>[
      if (label != null && label.isNotEmpty) label,
      if (usage is num)
        limit is num
            ? 'used \$${usage.toStringAsFixed(2)} of \$${limit.toStringAsFixed(2)}'
            : 'used \$${usage.toStringAsFixed(2)}',
    ];
    return parts.isEmpty ? 'Key accepted.' : 'Key accepted — ${parts.join(', ')}.';
  }

  /// Runs a chat turn: [system] is the briefing, [history] the conversation
  /// so far (oldest first). Returns the assistant's reply.
  Future<String> chat({
    required String system,
    required List<ChatTurn> history,
    int maxTokens = 2500,
  }) async {
    late final http.Response res;
    try {
      res = await _http.post(
        Uri.parse('$_base/chat/completions'),
        headers: _headers,
        body: jsonEncode({
          'model': model,
          'temperature': 0.3,
          'max_tokens': maxTokens,
          'messages': [
            {'role': 'system', 'content': system},
            for (final t in history) {'role': t.role, 'content': t.content},
          ],
        }),
      );
    } catch (e) {
      throw OpenRouterException('Could not reach OpenRouter: $e');
    }
    return parseCompletion(res.statusCode, res.body).trim();
  }

  /// Asks the chosen model for the nutrition of one serving of [food].
  /// The answer itself is a handful of numbers, but a reasoning model can
  /// spend thousands of tokens thinking before writing any of them, and a
  /// budget that runs out first returns nothing at all. This is sized for
  /// that, and [_estimateOnce] retries with more room if it still happens.
  static const _estimateTokens = 1500;

  Future<NutritionEstimate> estimate(String food, {String? note}) async {
    try {
      return await _estimateOnce(food, note: note, maxTokens: _estimateTokens);
    } on OpenRouterException catch (e) {
      if (!e.truncated) rethrow;
      // Thought its way through the whole budget. Give it a much larger one
      // before giving up, since a second failure is worth reporting.
      return _estimateOnce(food, note: note, maxTokens: _estimateTokens * 4);
    }
  }

  /// Identifies the foods in a photo and estimates each one.
  ///
  /// A plate usually holds several things, so this returns a list rather
  /// than a single estimate; the caller reviews it before anything is
  /// logged. The image is sent inline as a data URI and is not stored
  /// anywhere by this app.
  Future<List<NutritionEstimate>> estimateFromPhoto(
    Uint8List jpeg, {
    String? note,
  }) async {
    try {
      return await _photoOnce(jpeg, note: note, maxTokens: _photoTokens);
    } on OpenRouterException catch (e) {
      if (!e.truncated) rethrow;
      return _photoOnce(jpeg, note: note, maxTokens: _photoTokens * 3);
    }
  }

  /// Roomier than a name lookup: a plate can hold half a dozen items, each
  /// with its own line of JSON.
  static const _photoTokens = 2000;

  Future<List<NutritionEstimate>> _photoOnce(
    Uint8List jpeg, {
    String? note,
    required int maxTokens,
  }) async {
    late final http.Response res;
    try {
      res = await _http.post(
        Uri.parse('$_base/chat/completions'),
        headers: _headers,
        body: jsonEncode({
          'model': model,
          'temperature': 0.1,
          'max_tokens': maxTokens,
          'reasoning': {'enabled': false},
          'messages': [
            {'role': 'system', 'content': photoSystemPrompt},
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': note == null || note.isEmpty
                      ? 'What is in this photo?'
                      : 'What is in this photo? Extra detail: $note',
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,${base64Encode(jpeg)}',
                  },
                },
              ],
            },
          ],
        }),
      );
    } catch (e) {
      throw OpenRouterException('Could not reach OpenRouter: $e');
    }
    final content = parseCompletion(res.statusCode, res.body);
    return parsePhotoEstimate(content, model: model);
  }

  Future<NutritionEstimate> _estimateOnce(
    String food, {
    String? note,
    required int maxTokens,
  }) async {
    late final http.Response res;
    try {
      res = await _http.post(
        Uri.parse('$_base/chat/completions'),
        headers: _headers,
        body: jsonEncode({
          'model': model,
          'temperature': 0.1,
          'max_tokens': maxTokens,
          // Nothing here needs deliberation, and reasoning tokens are what
          // starve the answer. Models that cannot turn it off ignore this.
          'reasoning': {'enabled': false},
          'response_format': {'type': 'json_object'},
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {
              'role': 'user',
              'content': note == null || note.isEmpty
                  ? 'Food: $food'
                  : 'Food: $food\nExtra detail: $note',
            },
          ],
        }),
      );
    } catch (e) {
      throw OpenRouterException('Could not reach OpenRouter: $e');
    }
    final content = parseCompletion(res.statusCode, res.body);
    return parseEstimate(content, model: model);
  }

  Future<String> _get(Uri uri) async {
    late final http.Response res;
    try {
      res = await _http.get(uri, headers: _headers);
    } catch (e) {
      throw OpenRouterException('Could not reach OpenRouter: $e');
    }
    if (res.statusCode != 200) {
      throw OpenRouterException(_errorMessage(res.statusCode, res.body));
    }
    return res.body;
  }

  // ---- Pure helpers, kept static so they can be tested without network ----

  static const systemPrompt =
      'You estimate nutrition for foods, including Indian dishes. '
      'Reply with ONLY a JSON object, no prose and no code fences, with '
      'these keys: calories (number, kcal), protein_g (number), carbs_g '
      '(number), fat_g (number), serving (string describing the single '
      'serving the numbers are for, e.g. "1 cup (150 g)"), note (string, '
      'optional, at most 12 words). All figures are for ONE typical serving '
      'as commonly eaten, not per 100 g, unless the food name itself states '
      'a quantity. If the input is not a food, reply {"unknown": true}. '
      'Answer immediately with the JSON object; do not think it through '
      'first and do not write anything before or after it.';

  static const photoSystemPrompt =
      'You identify food in photographs, including Indian dishes, and '
      'estimate its nutrition. Reply with ONLY a JSON object, no prose and '
      'no code fences: {"items": [ ... ]}. Each item is one distinct food '
      'or drink visible in the photo, with these keys: name (string, short, '
      'what the food is called), calories (number, kcal), protein_g '
      '(number), carbs_g (number), fat_g (number), serving (string '
      'describing the portion you can see, e.g. "1 cup" or "2 pieces"). '
      'Estimate the portion from what is actually on the plate rather than '
      'a standard serving. List the components separately - rice, curry and '
      'salad are three items, not one. Add a top-level "note" (string, at '
      'most 15 words) for anything you had to assume or could not see. If '
      'the photo has no food in it, reply {"items": []}. Answer immediately '
      'with the JSON object; do not think it through first.';

  /// Reads the item list a vision model returns for a photo.
  static List<NutritionEstimate> parsePhotoEstimate(String content,
      {String? model}) {
    final json = _extractJson(content);
    if (json == null) {
      throw const OpenRouterException(
          'Could not read the model\'s answer as a list of foods.');
    }
    final items = json['items'];
    if (items is! List) {
      throw const OpenRouterException(
          'The model did not return a list of foods.');
    }
    if (items.isEmpty) {
      throw const OpenRouterException('No food was recognised in the photo.');
    }

    final sharedNote = _string(json['note']);
    final results = <NutritionEstimate>[];
    for (final item in items) {
      if (item is! Map) continue;
      final map = item.cast<String, Object?>();
      final name = _string(map['name']);
      if (name == null) continue;
      final estimate = _readFigures(
        map,
        name: name,
        model: model,
        source: NutritionEstimate.sourcePhoto,
        note: _string(map['note']) ?? sharedNote,
      );
      results.add(estimate);
    }
    if (results.isEmpty) {
      throw const OpenRouterException(
          'The model listed no foods it could name.');
    }
    return results;
  }

  static List<OpenRouterModel> parseModels(String body) {
    final decoded = jsonDecode(body);
    final list = decoded is Map ? decoded['data'] : decoded;
    if (list is! List) {
      throw const OpenRouterException('Unexpected model list from OpenRouter.');
    }
    final models = [
      for (final e in list)
        if (e is Map) OpenRouterModel.fromJson(e.cast<String, Object?>()),
    ]..removeWhere((m) => m.id.isEmpty);
    models.sort((a, b) => a.id.compareTo(b.id));
    return models;
  }

  /// Pulls the assistant message out of a chat-completions response, turning
  /// API errors into a readable message.
  static String parseCompletion(int statusCode, String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      decoded = null;
    }
    if (statusCode != 200) {
      throw OpenRouterException(_errorMessage(statusCode, body));
    }
    if (decoded is! Map) {
      throw const OpenRouterException('Unexpected reply from OpenRouter.');
    }
    // A 200 can still carry an error object.
    final err = decoded['error'];
    if (err is Map) {
      throw OpenRouterException(
          err['message']?.toString() ?? 'OpenRouter returned an error.');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const OpenRouterException('The model returned no answer.');
    }
    final choice = (choices.first as Map).cast<String, Object?>();
    final message = choice['message'];
    final content = message is Map ? message['content'] : null;
    if (content is String && content.trim().isNotEmpty) return content;

    // No content. A reasoning model that used its whole budget thinking
    // lands here with finish_reason 'length' and, on some providers, the
    // half-finished thoughts in a separate field.
    final truncated = choice['finish_reason'] == 'length' ||
        choice['native_finish_reason'] == 'length';
    if (truncated) {
      throw const OpenRouterException(
        'The model used its whole token budget thinking and never got to '
        'the answer. Reasoning models often do this - try a different one.',
        truncated: true,
      );
    }
    final reasoning = message is Map ? message['reasoning'] : null;
    if (reasoning is String && reasoning.trim().isNotEmpty) return reasoning;
    throw const OpenRouterException('The model returned an empty answer.');
  }

  /// Reads the model's JSON answer. Models sometimes wrap JSON in prose or
  /// code fences even when asked not to, so the object is located rather
  /// than assumed to be the whole string.
  static NutritionEstimate parseEstimate(String content, {String? model}) {
    final json = _extractJson(content);
    if (json == null) {
      throw const OpenRouterException(
          'Could not read the model\'s answer as nutrition data.');
    }
    if (json['unknown'] == true) {
      throw const OpenRouterException('The model did not recognise that food.');
    }

    final estimate = _readFigures(
      json,
      model: model,
      source: NutritionEstimate.sourceAi,
      note: _string(json['note']),
    );
    if (estimate.isEmpty) {
      throw const OpenRouterException(
          'The model did not return any nutrition figures.');
    }
    return estimate;
  }

  /// Pulls the nutrition numbers out of one JSON object, accepting both the
  /// key names the prompt asks for and the bare ones models drift to.
  static NutritionEstimate _readFigures(
    Map<String, Object?> json, {
    String? name,
    String? model,
    required String source,
    String? note,
  }) {
    double? number(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) {
        final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(v);
        if (m != null) return double.tryParse(m.group(0)!);
      }
      return null;
    }

    double? pick(List<String> keys) {
      for (final k in keys) {
        final v = number(json[k]);
        if (v != null && v >= 0) return v;
      }
      return null;
    }

    return NutritionEstimate(
      name: name,
      calories: pick(['calories', 'calories_kcal', 'kcal', 'energy_kcal']),
      protein: pick(['protein_g', 'protein', 'proteins_g']),
      carbs: pick(['carbs_g', 'carbs', 'carbohydrates_g', 'carbohydrates']),
      fat: pick(['fat_g', 'fat', 'fats_g', 'total_fat_g']),
      servingSize: _string(json['serving']) ?? _string(json['serving_size']),
      source: source,
      model: model,
      note: note,
    );
  }

  static String? _string(Object? v) {
    if (v is! String) return null;
    final s = v.trim();
    return s.isEmpty ? null : s;
  }

  static Map<String, Object?>? _extractJson(String content) {
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(content.substring(start, end + 1));
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  static String _errorMessage(int statusCode, String body) {
    String? detail;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        detail = (decoded['error'] as Map)['message']?.toString();
      }
    } catch (_) {
      // fall through to the status-based message
    }
    if (detail != null && detail.isNotEmpty) return detail;
    return switch (statusCode) {
      401 => 'OpenRouter rejected the API key.',
      402 => 'Not enough OpenRouter credit for this model.',
      429 => 'OpenRouter is rate limiting; try again shortly.',
      _ => 'OpenRouter returned HTTP $statusCode.',
    };
  }
}
