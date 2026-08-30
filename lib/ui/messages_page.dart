import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../services/sms_service.dart';
import 'compose_page.dart';
import 'thread_page.dart';

final _dateFmt = DateFormat('d MMM, h:mm a');

class _Conversation {
  final String sender;
  final SmsMessage last;
  final int count;
  final bool hasTransaction;
  final int unread;
  const _Conversation(
      this.sender, this.last, this.count, this.hasTransaction, this.unread);
}

/// SMS inbox grouped into one conversation per sender.
class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key});

  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

        // Search matches the sender or anything in the message text, so a
        // conversation surfaces even when only one old message matches.
        final q = _query.trim().toLowerCase();
        final filtered = q.isEmpty
            ? list
            : list
                .where((m) =>
                    m.sender.toLowerCase().contains(q) ||
                    m.body.toLowerCase().contains(q))
                .toList();

        if (filtered.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('No messages match "$_query"',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          );
        }

        // list is newest-first, so the first message seen per sender is the
        // conversation preview.
        final bySender = <String, List<SmsMessage>>{};
        for (final m in filtered) {
          bySender.putIfAbsent(m.sender, () => []).add(m);
        }
        final conversations = [
          for (final e in bySender.entries)
            _Conversation(
              e.key,
              e.value.first,
              e.value.length,
              e.value.any((m) => m.isTransaction),
              e.value.where((m) => !m.read && !m.outgoing).length,
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

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ComposePage()),
        ),
        child: const Icon(Icons.edit_outlined),
      ),
      body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search messages',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
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
      ),
    );
  }
}

/// Long-press menu on a conversation: mark unread or delete.
Future<void> _conversationActions(
  BuildContext context,
  WidgetRef ref,
  _Conversation c,
  String name,
) {
  final db = ref.read(dbProvider);
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.mark_email_unread_outlined),
            title: const Text('Mark as unread'),
            onTap: () async {
              await db.markThreadUnread(c.sender);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text('Delete conversation with $name'),
            subtitle: Text('${c.count} message${c.count == 1 ? '' : 's'}'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: sheetContext,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Delete conversation?'),
                  content: const Text(
                      'The messages are removed from this app. Transactions '
                      'already recorded from them are kept.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) await db.deleteThread(c.sender);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
        ],
      ),
    ),
  );
}

class _ConversationTile extends ConsumerWidget {
  final _Conversation conversation;
  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final name =
        ref.watch(contactNameProvider(c.sender)).valueOrNull ?? c.sender;
    final hasUnread = c.unread > 0;
    final scheme = Theme.of(context).colorScheme;

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
                style: TextStyle(
                    fontWeight:
                        hasUnread ? FontWeight.w800 : FontWeight.w600)),
          ),
          Text(_dateFmt.format(c.last.receivedAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: hasUnread ? FontWeight.w700 : null,
                    color: hasUnread ? scheme.primary : null,
                  )),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              '${c.last.outgoing ? 'You: ' : ''}${c.last.body}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: hasUnread
                  ? TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    )
                  : null,
            ),
          ),
          if (hasUnread)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: CircleAvatar(
                radius: 10,
                backgroundColor: scheme.primary,
                child: Text('${c.unread}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimary)),
              ),
            )
          else if (c.count > 1)
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
      onLongPress: () => _conversationActions(context, ref, c, name),
    );
  }
}
