import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/phone_service.dart';
import 'thread_page.dart';

/// The contact book, for calling and texting people by name.
class ContactsPage extends ConsumerStatefulWidget {
  const ContactsPage({super.key});

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final phone = ref.read(phoneServiceProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: 'New contact',
        onPressed: () async {
          await phone.addContact();
          // The editor is a separate app, so the list is reread on return
          // rather than assuming what was saved.
          ref.invalidate(contactsProvider);
        },
        child: const Icon(Icons.person_add_alt),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search contacts',
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
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: contacts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                if (all.isEmpty) {
                  return _Empty(
                    onGrant: () async {
                      await phone.requestPermissions();
                      ref.invalidate(contactsProvider);
                    },
                  );
                }
                final shown = [
                  for (final c in all)
                    if (c.matches(_query)) c,
                ];
                if (shown.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('No contacts match "$_query"',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(contactsProvider),
                  child: ListView.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _ContactTile(contact: shown[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onGrant;
  const _Empty({required this.onGrant});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.contacts_outlined,
                  size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text('No contacts',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Reading your contact book needs permission. Nothing is '
                'copied anywhere; it is read on the phone.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: onGrant,
                child: const Text('Grant permission'),
              ),
            ],
          ),
        ),
      );
}

class _ContactTile extends ConsumerWidget {
  final Contact contact;
  const _ContactTile({required this.contact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phone = ref.read(phoneServiceProvider);
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      // Initials rather than the photo: a contact photo is a content://
      // URI, which Flutter's image loaders cannot read without pulling the
      // bytes across the channel for every row.
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(contact.initial,
            style: TextStyle(color: scheme.onPrimaryContainer)),
      ),
      title: Text(contact.name.isEmpty ? contact.number : contact.name),
      subtitle: Text([
        ?contact.label,
        contact.number,
      ].join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Message',
            icon: const Icon(Icons.sms_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ThreadPage(
                  sender: contact.number,
                  displayName: contact.name,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Call',
            icon: const Icon(Icons.call),
            onPressed: () => phone.call(contact.number),
          ),
        ],
      ),
      onTap: () => phone.openContact(contact.id),
    );
  }
}
