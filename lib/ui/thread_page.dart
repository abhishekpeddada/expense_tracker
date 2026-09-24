import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/db.dart';
import '../data/providers.dart';
import '../parsing/message_links.dart';
import '../services/sms_service.dart';
import 'compose_page.dart';
import 'message_body.dart';

final _timeFmt = DateFormat('d MMM, h:mm a');

final _threadProvider =
    StreamProvider.family<List<SmsMessage>, String>((ref, sender) {
  return ref.watch(dbProvider).watchThread(sender);
});

/// One conversation: all messages with a sender, plus a reply box.
class ThreadPage extends ConsumerStatefulWidget {
  final String sender;
  final String displayName;
  const ThreadPage(
      {super.key, required this.sender, required this.displayName});

  @override
  ConsumerState<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends ConsumerState<ThreadPage> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Opening the thread clears its unread state (bold in the inbox).
    ref.read(dbProvider).markThreadRead(widget.sender);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(smsServiceProvider)
          .sendSms(to: widget.sender, body: text);
      _controller.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// What to do with a number found inside a message. Calling is the
  /// obvious one, but a number in a bank SMS is as often something to text
  /// or to save.
  Future<void> _phoneActions(BuildContext context, String shown) async {
    final digits = shown.replaceAll(RegExp(r'[\s-]'), '');
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(shown,
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.call_outlined),
              title: const Text('Call'),
              onTap: () {
                Navigator.pop(sheetContext);
                launchUrl(Uri.parse('tel:$digits'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('Send a message'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ComposePage(to: digits)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy number'),
              onTap: () {
                Navigator.pop(sheetContext);
                Clipboard.setData(ClipboardData(text: digits));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied $digits')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press menu on a message: forward it, copy it, share it out, grab
  /// the code in it, or delete it.
  Future<void> _messageActions(BuildContext context, SmsMessage m) async {
    final code = MessageLinks.code(m.body);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (code != null)
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: Text('Copy code $code'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied $code')),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.forward_outlined),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ComposePage(body: m.body),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy text'),
              onTap: () {
                Navigator.pop(sheetContext);
                Clipboard.setData(ClipboardData(text: m.body));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share outside the app'),
              onTap: () {
                Navigator.pop(sheetContext);
                SharePlus.instance.share(ShareParams(text: m.body));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete message'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(dbProvider).deleteMessage(m.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(_threadProvider(widget.sender));
    // Shortcode senders (banks, promos) can't receive replies.
    final canReply = RegExp(r'^\+?\d{7,}$').hasMatch(widget.sender);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.displayName, style: const TextStyle(fontSize: 18)),
            if (widget.displayName != widget.sender)
              Text(widget.sender,
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Delete conversation',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final ok = await showDialog<bool>(
                context: context,
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
              if (ok != true) return;
              await ref.read(dbProvider).deleteThread(widget.sender);
              navigator.pop();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: msgs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) => ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final m = list[list.length - 1 - i];
                  return _Bubble(
                    message: m,
                    onPhone: (number) => _phoneActions(context, number),
                    onLongPress: () => _messageActions(context, m),
                  );
                },
              ),
            ),
          ),
          if (canReply)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Text message',
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.all(Radius.circular(24)),
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final SmsMessage message;
  final void Function(String number) onPhone;
  final VoidCallback onLongPress;

  const _Bubble({
    required this.message,
    required this.onPhone,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.outgoing;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MessageBody(body: message.body, onPhone: onPhone),
            const SizedBox(height: 2),
            Text(
              _timeFmt.format(message.receivedAt),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.outline),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
