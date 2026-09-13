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

  /// Senders picked in selection mode. Selection is by conversation, which
  /// is what the list shows; acting on it covers every message inside.
  final _selected = <String>{};

  /// True once selection mode is entered, even with nothing picked yet, so
  /// the toolbar stays up while choosing.
  bool _selecting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Groups messages into one conversation per sender, applying the search.
  List<_Conversation> _conversations(List<SmsMessage> all) {
    // Search matches the sender or anything in the message text, so a
    // conversation surfaces even when only one old message matches.
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? all
        : all
            .where((m) =>
                m.sender.toLowerCase().contains(q) ||
                m.body.toLowerCase().contains(q))
            .toList();

    // all is newest-first, so the first message seen per sender is the
    // conversation preview.
    final bySender = <String, List<SmsMessage>>{};
    for (final m in filtered) {
      bySender.putIfAbsent(m.sender, () => []).add(m);
    }
    return [
      for (final e in bySender.entries)
        _Conversation(
          e.key,
          e.value.first,
          e.value.length,
          e.value.any((m) => m.isTransaction),
          e.value.where((m) => !m.read && !m.outgoing).length,
        ),
    ];
  }

  void _startSelecting([String? sender]) {
    setState(() {
      _selecting = true;
      if (sender != null) _selected.add(sender);
    });
  }

  void _toggle(String sender) {
    setState(() {
      if (!_selected.remove(sender)) _selected.add(sender);
    });
  }

  void _endSelecting() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _markSelectedRead() async {
    final senders = _selected.toList();
    final messenger = ScaffoldMessenger.of(context);
    final changed = await ref.read(dbProvider).markThreadsRead(senders);
    _endSelecting();
    messenger.showSnackBar(SnackBar(
      content: Text(changed == 0
          ? 'Nothing was unread'
          : 'Marked $changed message${changed == 1 ? '' : 's'} as read'),
    ));
  }

  Future<void> _markSelectedUnread() async {
    final count = _selected.length;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(dbProvider).markThreadsUnread(_selected.toList());
    _endSelecting();
    messenger.showSnackBar(SnackBar(
      content: Text(
          'Marked $count conversation${count == 1 ? '' : 's'} as unread'),
    ));
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $count conversation${count == 1 ? '' : 's'}?'),
        content: const Text(
            'The messages are removed from this app. Transactions already '
            'recorded from them are kept.'),
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
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(dbProvider).deleteThreads(_selected.toList());
    _endSelecting();
    messenger.showSnackBar(SnackBar(
      content:
          Text('Deleted $count conversation${count == 1 ? '' : 's'}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(messagesProvider);
    final isDefault = ref.watch(isDefaultSmsAppProvider).valueOrNull ?? true;

    final all = msgs.valueOrNull ?? const <SmsMessage>[];
    final conversations = _conversations(all);

    // Senders still in the inbox, which is what a selection may refer to.
    // Searching narrows what is on screen but must not silently drop
    // conversations already picked; only a deleted thread does that.
    final existing = {for (final m in all) m.sender};
    _selected.retainWhere(existing.contains);

    final visible = {for (final c in conversations) c.sender};
    final allVisibleSelected =
        visible.isNotEmpty && _selected.containsAll(visible);

    final Widget body;
    if (msgs.isLoading && all.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (msgs.hasError) {
      body = Center(child: Text('Error: ${msgs.error}'));
    } else if (all.isEmpty) {
      body = Center(
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
    } else if (conversations.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No messages match "$_query"',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    } else {
      body = ListView.separated(
        itemCount: conversations.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final c = conversations[i];
          return _ConversationTile(
            conversation: c,
            selecting: _selecting,
            selected: _selected.contains(c.sender),
            onToggle: () => _toggle(c.sender),
            onStartSelecting: () => _startSelecting(c.sender),
          );
        },
      );
    }

    return Scaffold(
      // The compose button would sit over the selection actions, and there
      // is nothing to compose while picking conversations.
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ComposePage()),
              ),
              child: const Icon(Icons.edit_outlined),
            ),
      body: Column(
        children: [
          if (_selecting)
            _SelectionBar(
              count: _selected.length,
              allSelected: allVisibleSelected,
              onClose: _endSelecting,
              onSelectAll: () => setState(() {
                if (allVisibleSelected) {
                  _selected.removeAll(visible);
                } else {
                  _selected.addAll(visible);
                }
              }),
              onMarkRead: _markSelectedRead,
              onMarkUnread: _markSelectedUnread,
              onDelete: _deleteSelected,
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
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
                  if (conversations.isNotEmpty)
                    IconButton(
                      tooltip: 'Select conversations',
                      icon: const Icon(Icons.checklist),
                      onPressed: _startSelecting,
                    ),
                ],
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

/// Replaces the search field while conversations are being picked.
class _SelectionBar extends StatelessWidget {
  final int count;

  /// Every conversation currently on screen is picked, so the button
  /// offers to clear rather than select again.
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;
  final VoidCallback onDelete;

  const _SelectionBar({
    required this.count,
    required this.allSelected,
    required this.onClose,
    required this.onSelectAll,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final none = count == 0;

    return Material(
      color: scheme.secondaryContainer,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Done',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
            Expanded(
              child: Text(
                none ? 'Select conversations' : '$count selected',
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: allSelected ? 'Clear selection' : 'Select all',
              icon: Icon(allSelected
                  ? Icons.deselect
                  : Icons.select_all),
              onPressed: onSelectAll,
            ),
            IconButton(
              tooltip: 'Mark as read',
              icon: const Icon(Icons.mark_email_read_outlined),
              onPressed: none ? null : onMarkRead,
            ),
            IconButton(
              tooltip: 'Mark as unread',
              icon: const Icon(Icons.mark_email_unread_outlined),
              onPressed: none ? null : onMarkUnread,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: none ? null : onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Long-press menu on a conversation: start selecting, mark read or
/// unread, or delete it.
Future<void> _conversationActions(
  BuildContext context,
  WidgetRef ref,
  _Conversation c,
  String name,
  VoidCallback onStartSelecting,
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
            leading: const Icon(Icons.checklist),
            title: const Text('Select'),
            subtitle: const Text('Pick several, then mark read or delete'),
            onTap: () {
              Navigator.pop(sheetContext);
              onStartSelecting();
            },
          ),
          ListTile(
            leading: const Icon(Icons.mark_email_read_outlined),
            title: const Text('Mark as read'),
            onTap: () async {
              await db.markThreadRead(c.sender);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
          ),
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
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onStartSelecting;

  const _ConversationTile({
    required this.conversation,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onStartSelecting,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conversation;
    final name =
        ref.watch(contactNameProvider(c.sender)).valueOrNull ?? c.sender;
    final hasUnread = c.unread > 0;
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.4),
      leading: selecting
          ? Checkbox(
              value: selected,
              onChanged: (_) => onToggle(),
            )
          : CircleAvatar(
              child: Icon(c.hasTransaction
                  ? Icons.currency_rupee
                  : Icons.person_outline),
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
      // While picking, a tap toggles rather than opens - opening would mark
      // the thread read, which is the opposite of a considered choice.
      onTap: selecting
          ? onToggle
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ThreadPage(sender: c.sender, displayName: name),
                ),
              ),
      onLongPress:
          selecting ? onToggle : () => _conversationActions(context, ref, c, name, onStartSelecting),
    );
  }
}
