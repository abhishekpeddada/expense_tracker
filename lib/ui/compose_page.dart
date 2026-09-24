import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sms_service.dart';
import 'thread_page.dart';

/// Starts a new conversation with any number.
class ComposePage extends ConsumerStatefulWidget {
  /// Prefilled recipient, when the number is already known.
  final String? to;

  /// Prefilled text, which is how forwarding a message works: the body
  /// travels, the recipient is chosen here.
  final String? body;

  const ComposePage({super.key, this.to, this.body});

  @override
  ConsumerState<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends ConsumerState<ComposePage> {
  late final _to = TextEditingController(text: widget.to ?? '');
  late final _body = TextEditingController(text: widget.body ?? '');
  bool _sending = false;

  bool get _isForward => widget.body != null;

  @override
  void dispose() {
    _to.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final to = _to.text.trim();
    final body = _body.text.trim();
    if (to.isEmpty || body.isEmpty || _sending) return;

    setState(() => _sending = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(smsServiceProvider).sendSms(to: to, body: body);
      navigator.pushReplacement(MaterialPageRoute(
        builder: (_) => ThreadPage(sender: to, displayName: to),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_isForward ? 'Forward message' : 'New message')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _to,
              // Forwarding already has the text; the recipient is what is
              // missing.
              autofocus: widget.to == null,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'To',
                hintText: 'Phone number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _body,
              autofocus: widget.to != null && widget.body == null,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send),
                label: const Text('Send'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
