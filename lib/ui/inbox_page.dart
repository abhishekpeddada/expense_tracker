import 'package:flutter/material.dart';

import 'calls_page.dart';
import 'messages_page.dart';

/// Messages and calls, which are the same tab: both are "who contacted me".
///
/// A seventh navigation destination would not fit, and these two belong
/// together anyway - a missed call and an unread SMS from the same person
/// are one thought.
class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

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
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [MessagesPage(), CallsPage()],
          ),
        ),
      ],
    );
  }
}
