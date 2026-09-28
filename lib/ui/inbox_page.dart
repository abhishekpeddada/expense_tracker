import 'package:flutter/material.dart';

import 'calls_page.dart';
import 'contacts_page.dart';
import 'messages_page.dart';

/// Messages, calls and contacts: everything about people, in one tab.
///
/// A seventh navigation destination would not fit, and these belong
/// together anyway - a missed call and an unread SMS from the same person
/// are one thought, and the contact book is who both of them are.
class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Messages', icon: Icon(Icons.chat_bubble_outline)),
            Tab(text: 'Calls', icon: Icon(Icons.call_outlined)),
            Tab(text: 'Contacts', icon: Icon(Icons.person_outline)),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [MessagesPage(), CallsPage(), ContactsPage()],
          ),
        ),
      ],
    );
  }
}
