import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../services/chat_service.dart';
import '../services/settings_service.dart';
import 'settings_page.dart';

final _timeFmt = DateFormat('d MMM, h:mm a');

/// Ask questions about your own spending and eating, with follow-ups.
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || ref.read(chatBusyProvider)) return;
    if (!ref.read(settingsProvider).hasKey) {
      _promptForKey();
      return;
    }
    _input.clear();
    FocusScope.of(context).unfocus();
    await ref.read(chatBusyProvider.notifier).ask(text);
  }

  void _promptForKey() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Add an OpenRouter key to use chat.'),
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

  /// Keeps the newest turn in view as the thread grows.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages =
        ref.watch(chatMessagesProvider).valueOrNull ?? const <ChatMessage>[];
    final busy = ref.watch(chatBusyProvider);
    final hasKey = ref.watch(settingsProvider).hasKey;

    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      _scrollToEnd();
    }

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? _Empty(hasKey: hasKey, onPick: _send)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  itemCount: messages.length + (busy ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= messages.length) return const _Thinking();
                    return _Bubble(message: messages[i]);
                  },
                ),
        ),
        if (messages.isNotEmpty && !busy)
          _FollowUps(onPick: _send),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: hasKey
                          ? 'Ask about your spending or food'
                          : 'Add an OpenRouter key in Settings first',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: busy ? null : () => _send(),
                  icon: busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == 'user';
    final background = message.isError
        ? scheme.errorContainer
        : isUser
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    final foreground = message.isError
        ? scheme.onErrorContainer
        : isUser
            ? scheme.onPrimaryContainer
            : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: message.content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied')),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.isError)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 16, color: foreground),
                        const SizedBox(width: 6),
                        Text('Could not answer',
                            style: TextStyle(
                                color: foreground,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                SelectableText(
                  message.content,
                  style: TextStyle(color: foreground, height: 1.35),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    _timeFmt.format(message.createdAt),
                    ?message.model,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground.withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text('Looking through your data...',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  final bool hasKey;
  final ValueChanged<String> onPick;
  const _Empty({required this.hasKey, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Icon(Icons.forum_outlined,
            size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Ask about your money and meals',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          hasKey
              ? 'Your transactions, accounts, budgets and food log are sent '
                  'with each question, so answers are about your own data. '
                  'Follow-up questions keep the thread.'
              : 'This needs an OpenRouter API key. Add one in Settings and '
                  'the assistant can answer questions about your own '
                  'transactions, budgets and food log.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final s in ChatService.starters)
              ActionChip(label: Text(s), onPressed: () => onPick(s)),
          ],
        ),
      ],
    );
  }
}

/// A couple of quick follow-ups once a thread is going.
class _FollowUps extends StatelessWidget {
  final ValueChanged<String> onPick;
  const _FollowUps({required this.onPick});

  static const _prompts = [
    'Why?',
    'Show the numbers',
    'What should I do about it?',
    'Compare with last month',
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final p in _prompts)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(p),
                  onPressed: () => onPick(p),
                ),
              ),
          ],
        ),
      );
}

/// Shows exactly what the app sends with each question.
class ChatContextPage extends ConsumerWidget {
  const ChatContextPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('What gets sent')),
      body: FutureBuilder<String>(
        future: ref.read(chatServiceProvider).briefing(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'This summary goes to OpenRouter with every question, along '
                'with the conversation so far. Raw SMS text is never '
                'included.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SelectableText(
                snapshot.data!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}
