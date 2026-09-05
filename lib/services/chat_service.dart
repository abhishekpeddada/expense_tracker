import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../data/providers.dart';
import 'chat_context.dart';
import 'openrouter.dart';
import 'settings_service.dart';

/// Drives the Chat tab: gathers the current picture of spending and eating,
/// sends it with the conversation so far, and stores the reply.
///
/// The briefing is rebuilt on every turn rather than sent once, so an answer
/// always reflects transactions and meals recorded since the conversation
/// started.
class ChatService {
  ChatService(this._ref);

  final Ref _ref;

  /// How many earlier turns are replayed. Enough for follow-ups to make
  /// sense without the request growing without limit.
  static const historyTurns = 20;

  AppDb get _db => _ref.read(dbProvider);

  bool get isConfigured => _ref.read(openRouterProvider) != null;

  /// Builds the briefing that would be sent right now. Exposed so the UI can
  /// show the person exactly what leaves the device.
  Future<String> briefing() async {
    final transactions = await _db.watchTransactions().first;
    final budgets = await _db.watchBudgets().first;
    final food = await _db.watchFoodEntries().first;
    final accounts = _ref.read(accountsProvider);
    return ChatContext.build(
      transactions: transactions,
      budgets: budgets,
      food: food,
      accounts: accounts,
    );
  }

  /// Records the question, asks the model, and records the answer. Errors
  /// are stored as error turns so the thread shows what went wrong instead
  /// of silently dropping the question.
  Future<void> send(String question) async {
    final text = question.trim();
    if (text.isEmpty) return;

    await _db.insertChatMessage(ChatMessagesCompanion.insert(
      role: 'user',
      content: text,
      createdAt: Value(DateTime.now()),
    ));

    final client = _ref.read(openRouterProvider);
    if (client == null) {
      await _fail('Add an OpenRouter API key in Settings to use chat.');
      return;
    }

    try {
      final stored = await _db.chatHistory();
      final history = [
        for (final m in stored)
          // Error notices are UI only: replaying them would have the model
          // apologising for something the person never said.
          if (!m.isError) ChatTurn(m.role, m.content),
      ];
      final trimmed = history.length > historyTurns
          ? history.sublist(history.length - historyTurns)
          : history;

      final reply = await client.chat(
        system: await briefing(),
        history: trimmed,
      );
      await _db.insertChatMessage(ChatMessagesCompanion.insert(
        role: 'assistant',
        content: reply,
        model: Value(client.model),
        createdAt: Value(DateTime.now()),
      ));
    } on OpenRouterException catch (e) {
      await _fail(e.message);
    } catch (e) {
      await _fail('Something went wrong: $e');
    }
  }

  Future<void> _fail(String message) => _db.insertChatMessage(
        ChatMessagesCompanion.insert(
          role: 'assistant',
          content: message,
          isError: const Value(true),
          createdAt: Value(DateTime.now()),
        ),
      );

  Future<void> clear() => _db.clearChat();

  /// Openers offered on an empty thread, picked to match what the app
  /// actually holds.
  static const starters = [
    'Where is my money going this month?',
    'What can I cut back on?',
    'Any subscriptions I should cancel?',
    'How does this month compare with last month?',
    'What am I eating too much of?',
    'Is my spending on food and dining reasonable?',
  ];
}

final chatServiceProvider = Provider<ChatService>(ChatService.new);

final chatMessagesProvider = StreamProvider<List<ChatMessage>>(
  (ref) => ref.watch(dbProvider).watchChat(),
);

/// True while a reply is being waited on, so the UI can show a spinner and
/// keep the send button disabled.
final chatBusyProvider =
    NotifierProvider<ChatBusyNotifier, bool>(ChatBusyNotifier.new);

class ChatBusyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> ask(String question) async {
    if (state) return;
    state = true;
    try {
      await ref.read(chatServiceProvider).send(question);
    } finally {
      state = false;
    }
  }
}
