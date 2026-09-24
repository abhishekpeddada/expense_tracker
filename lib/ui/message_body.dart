import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../parsing/message_links.dart';

/// Message text with its links, phone numbers, emails and codes tappable.
///
/// Recognisers have to be created per build and disposed, so this is a
/// stateful widget rather than a plain Text.
class MessageBody extends StatefulWidget {
  final String body;
  final TextStyle? style;

  /// Called when a phone number is tapped, so the thread can offer to text
  /// it as well as call it.
  final void Function(String number)? onPhone;

  const MessageBody({
    super.key,
    required this.body,
    this.style,
    this.onPhone,
  });

  @override
  State<MessageBody> createState() => _MessageBodyState();
}

class _MessageBodyState extends State<MessageBody> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(BuildContext context, MessagePart part) async {
    final messenger = ScaffoldMessenger.of(context);

    if (part.kind == LinkKind.code) {
      await Clipboard.setData(ClipboardData(text: part.text));
      messenger.showSnackBar(
          SnackBar(content: Text('Copied ${part.text}')));
      return;
    }
    if (part.kind == LinkKind.phone && widget.onPhone != null) {
      widget.onPhone!(part.text);
      return;
    }

    final uri = Uri.tryParse(part.value!);
    if (uri == null) return;
    // An app that can handle it may simply not be installed - a phone
    // without a browser, or a tablet with no dialler.
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text('Nothing on this phone opens ${part.text}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final parts = MessageLinks.parse(widget.body);
    if (parts.every((p) => !p.isLink)) {
      return SelectableText(widget.body, style: widget.style);
    }

    final linkStyle = (widget.style ?? const TextStyle()).copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );

    return SelectableText.rich(
      TextSpan(
        style: widget.style,
        children: [
          for (final part in parts)
            if (!part.isLink)
              TextSpan(text: part.text)
            else
              TextSpan(
                text: part.text,
                style: linkStyle,
                recognizer: _register(part),
              ),
        ],
      ),
    );
  }

  TapGestureRecognizer _register(MessagePart part) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => _open(context, part);
    _recognizers.add(recognizer);
    return recognizer;
  }
}
