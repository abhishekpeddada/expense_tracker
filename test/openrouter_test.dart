import 'dart:convert';

import 'package:expense_tracker/nutrition/nutrition.dart';
import 'package:expense_tracker/services/openrouter.dart';
import 'package:flutter_test/flutter_test.dart';

String completion(String content) => jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content}
        }
      ]
    });

void main() {
  group('model list', () {
    test('parses ids, pricing and context', () {
      final models = OpenRouterClient.parseModels(jsonEncode({
        'data': [
          {
            'id': 'openai/gpt-4o-mini',
            'name': 'GPT-4o mini',
            'context_length': 128000,
            'pricing': {'prompt': '0.00000015', 'completion': '0.0000006'},
          },
          {
            'id': 'meta-llama/llama-3-8b:free',
            'name': 'Llama 3 8B (free)',
            'context_length': 8192,
            'pricing': {'prompt': '0', 'completion': '0'},
          },
        ]
      }));

      expect(models, hasLength(2));
      final free = models.firstWhere((m) => m.id.endsWith(':free'));
      expect(free.isFree, isTrue);
      expect(free.priceLabel, 'Free');
      expect(free.vendor, 'meta-llama');

      final paid = models.firstWhere((m) => m.id == 'openai/gpt-4o-mini');
      expect(paid.isFree, isFalse);
      expect(paid.contextLabel, '128K ctx');
      expect(paid.priceLabel, contains('0.15'));
    });

    test('falls back to the id when a model has no name', () {
      final models = OpenRouterClient.parseModels(
          jsonEncode({'data': [{'id': 'some/model'}]}));
      expect(models.single.name, 'some/model');
      expect(models.single.promptPrice, isNull);
    });

    test('rejects an unexpected shape', () {
      expect(() => OpenRouterClient.parseModels('{"nope":true}'),
          throwsA(isA<OpenRouterException>()));
    });
  });

  group('completion envelope', () {
    test('returns the assistant message', () {
      expect(OpenRouterClient.parseCompletion(200, completion('hi')), 'hi');
    });

    test('surfaces the API error message on a failure status', () {
      expect(
        () => OpenRouterClient.parseCompletion(
            401, jsonEncode({'error': {'message': 'No auth credentials'}})),
        throwsA(isA<OpenRouterException>().having(
            (e) => e.message, 'message', 'No auth credentials')),
      );
    });

    test('explains a bare failure status', () {
      expect(
        () => OpenRouterClient.parseCompletion(402, 'nope'),
        throwsA(isA<OpenRouterException>()
            .having((e) => e.message, 'message', contains('credit'))),
      );
    });

    test('catches an error object returned with HTTP 200', () {
      expect(
        () => OpenRouterClient.parseCompletion(
            200, jsonEncode({'error': {'message': 'Rate limited'}})),
        throwsA(isA<OpenRouterException>()
            .having((e) => e.message, 'message', 'Rate limited')),
      );
    });

    test('rejects an empty answer', () {
      expect(() => OpenRouterClient.parseCompletion(200, completion('   ')),
          throwsA(isA<OpenRouterException>()));
    });

    test('a reasoning model that thought past its budget is truncated', () {
      // What minimax-m2.7 actually returns: all the tokens went to
      // reasoning, the content is empty, finish_reason is length.
      final body = jsonEncode({
        'choices': [
          {
            'finish_reason': 'length',
            'native_finish_reason': 'length',
            'message': {'role': 'assistant', 'content': ''},
          }
        ]
      });
      expect(
        () => OpenRouterClient.parseCompletion(200, body),
        throwsA(isA<OpenRouterException>()
            .having((e) => e.truncated, 'truncated', isTrue)
            .having((e) => e.message, 'message', contains('thinking'))),
      );
    });

    test('falls back to the reasoning field when content is empty', () {
      final body = jsonEncode({
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {
              'role': 'assistant',
              'content': '',
              'reasoning': 'The answer is {"calories": 58}',
            },
          }
        ]
      });
      expect(OpenRouterClient.parseCompletion(200, body),
          contains('"calories": 58'));
    });

    test('an ordinary empty answer is not marked truncated', () {
      expect(
        () => OpenRouterClient.parseCompletion(200, completion('')),
        throwsA(isA<OpenRouterException>()
            .having((e) => e.truncated, 'truncated', isFalse)),
      );
    });

    test('content that arrived before truncation is still used', () {
      final body = jsonEncode({
        'choices': [
          {
            'finish_reason': 'length',
            'message': {'role': 'assistant', 'content': '{"calories": 58}'},
          }
        ]
      });
      expect(OpenRouterClient.parseCompletion(200, body),
          '{"calories": 58}');
    });
  });

  group('nutrition answer', () {
    test('reads the requested keys', () {
      final e = OpenRouterClient.parseEstimate(
        '{"calories": 133, "protein_g": 2.7, "carbs_g": 25.6, '
        '"fat_g": 3.7, "serving": "1 plain dosa", "note": "no filling"}',
        model: 'openai/gpt-4o-mini',
      );
      expect(e.calories, 133);
      expect(e.protein, closeTo(2.7, 0.001));
      expect(e.carbs, closeTo(25.6, 0.001));
      expect(e.fat, closeTo(3.7, 0.001));
      expect(e.servingSize, '1 plain dosa');
      expect(e.note, 'no filling');
      expect(e.source, NutritionEstimate.sourceAi);
      expect(e.model, 'openai/gpt-4o-mini');
      expect(e.hasMacros, isTrue);
    });

    test('digs the object out of prose and code fences', () {
      const content =
          'Sure! Here you go:\n```json\n{"calories": 58, "protein_g": 2}\n```\n'
          'Hope that helps.';
      final e = OpenRouterClient.parseEstimate(content);
      expect(e.calories, 58);
      expect(e.protein, 2);
    });

    test('accepts the alternative key names models drift to', () {
      final e = OpenRouterClient.parseEstimate(
          '{"kcal": 210, "protein": 6, "carbohydrates_g": 30, '
          '"total_fat_g": 8, "serving_size": "1 cup"}');
      expect(e.calories, 210);
      expect(e.protein, 6);
      expect(e.carbs, 30);
      expect(e.fat, 8);
      expect(e.servingSize, '1 cup');
    });

    test('reads numbers written as strings with units', () {
      final e = OpenRouterClient.parseEstimate(
          '{"calories": "250 kcal", "protein_g": "8 g"}');
      expect(e.calories, 250);
      expect(e.protein, 8);
    });

    test('reports a food the model could not identify', () {
      expect(
        () => OpenRouterClient.parseEstimate('{"unknown": true}'),
        throwsA(isA<OpenRouterException>()
            .having((e) => e.message, 'message', contains('recognise'))),
      );
    });

    test('rejects an answer with no figures at all', () {
      expect(() => OpenRouterClient.parseEstimate('{"serving": "1 cup"}'),
          throwsA(isA<OpenRouterException>()));
    });

    test('rejects an answer that is not JSON', () {
      expect(() => OpenRouterClient.parseEstimate('I am not sure.'),
          throwsA(isA<OpenRouterException>()));
    });
  });
}
