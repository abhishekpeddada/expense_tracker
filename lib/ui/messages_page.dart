import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/providers.dart';

final _dateFmt = DateFormat('d MMM, h:mm a');

/// SMS inbox. For now it lists messages stored in the local DB; the native
/// default-SMS-app layer will feed real incoming SMS into that DB.
class MessagesPage extends ConsumerWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msgs = ref.watch(messagesProvider);
    return msgs.when(
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
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final m = list[i];
            return ListTile(
              leading: CircleAvatar(
                child: Icon(m.isTransaction
                    ? Icons.currency_rupee
                    : Icons.person_outline),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(m.sender,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text(_dateFmt.format(m.receivedAt),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              subtitle:
                  Text(m.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            );
          },
        );
      },
    );
  }
}
