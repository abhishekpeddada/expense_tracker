import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../services/sms_service.dart';
import 'thread_page.dart';

final _dateFmt = DateFormat('d MMM, h:mm a');

class _Conversation {
  final String sender;
  final SmsMessage last;
  final int count;
  final bool hasTransaction;
  const _Conversation(this.sender, this.last, this.count, this.hasTransaction);
}

/// SMS inbox grouped into one conversation per sender.
class MessagesPage extends ConsumerWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msgs = ref.watch(messagesProvider);
    final isDefault = ref.watch(isDefaultSmsAppProvider).valueOrNull ?? true;

    final body = msgs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sms_outlined,
                      size: 56, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('No messages',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Set this app as your default SMS app and incoming '
                    'messages will appear here.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        }

        // list is newest-first, so the first message seen per sender is the
        // conversation preview.
        final bySender = <String, List<SmsMessage>>{};
        for (final m in list) {
          bySender.putIfAbsent(m.sender, () => []).add(m);
        }
        final conversations = [
          for (final e in bySender.entries)
            _Conversation(
              e.key,
              e.value.first,
              e.value.length,
              e.value.any((m) => m.isTransaction),
            ),
        ];

        return ListView.separated(
          itemCount: conversations.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) =>
              _ConversationTile(conversation: conversations[i]),
        );
      },
    );

    return Column(
      children: [
        if (!isDefault)
          MaterialBanner(
            content: const Text(
              'Expense Tracker is not your default SMS app, so it cannot '
              'see incoming bank messages.',
            ),
            leading: const Icon(Icons.sms_failed_outlined),
            actions: [
              TextButton(
                onPressed: () async {
                  await ref.read(smsServiceProvider).requestDefaultSmsRole();
                  ref.invalidate(isDefaultSmsAppProvider);
                },
                child: const Text('MAKE DEFAULT'),
              ),
            ],
          ),
        Expanded(child: body),
      ],
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  final _Conversation conversation;
  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final name =
        ref.watch(contactNameProvider(c.sender)).valueOrNull ?? c.sender;

    return ListTile(
      leading: CircleAvatar(
        child: Icon(
            c.hasTransaction ? Icons.currency_rupee : Icons.person_outline),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text(_dateFmt.format(c.last.receivedAt),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              '${c.last.outgoing ? 'You: ' : ''}${c.last.body}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (c.count > 1)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('${c.count}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ThreadPage(sender: c.sender, displayName: name),
        ),
      ),
    );
  }
}
