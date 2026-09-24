/// Finds the actionable bits inside a message body: links, phone numbers,
/// email addresses and one-time codes.
library;

enum LinkKind { url, email, phone, code }

/// A stretch of the message body, either plain text or something tappable.
class MessagePart {
  final String text;

  /// Null for ordinary text.
  final LinkKind? kind;

  /// What the action uses, which is not always what is shown: a phone
  /// number loses its spaces, a link gains a scheme.
  final String? value;

  const MessagePart.plain(this.text)
      : kind = null,
        value = null;
  const MessagePart.link(this.text, this.kind, this.value);

  bool get isLink => kind != null;
}

class _Match {
  final int start;
  final int end;
  final LinkKind kind;
  final String text;
  final String value;
  const _Match(this.start, this.end, this.kind, this.text, this.value);
}

class MessageLinks {
  /// A link with a scheme, or one starting www., or a bare domain that has
  /// a path. The path requirement keeps "Rs.500" and "a/c no." out.
  static final _urlRe = RegExp(
    r'\b(?:https?://|www\.)[^\s<>"]+'
    r'|\b[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)+/[^\s<>"]*',
    caseSensitive: false,
  );

  static final _emailRe = RegExp(
    r'\b[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\b',
    caseSensitive: false,
  );

  /// Indian mobile numbers, optionally with a country code and grouped with
  /// spaces or hyphens, plus toll-free numbers banks print for support.
  ///
  /// A bare ten-digit run has to start 6-9 to be a mobile, which is what
  /// keeps account numbers and amounts from being offered as calls.
  static final _phoneRe = RegExp(
    r'(?<![\d/-])(?:'
    r'\+91[\s-]?[6-9]\d{4}[\s-]?\d{5}'
    r'|0?1800[\s-]?\d{3}[\s-]?\d{3,4}'
    r'|[6-9]\d{4}[\s-]?\d{5}'
    r')(?![\d-])',
  );

  /// Words that mean the digits nearby are a code to type in somewhere.
  static final _codeContextRe = RegExp(
    r'\b(otp|o\.t\.p|one[\s-]?time[\s-]?(?:password|pin|code)|'
    r'verification code|security code|passcode|'
    r'pin|code)\b',
    caseSensitive: false,
  );

  /// The code itself: four to eight digits standing on their own.
  static final _codeRe = RegExp(r'(?<![\d.,])\d{4,8}(?![\d.,]\d)');

  /// Splits [body] into plain and tappable parts, in order.
  static List<MessagePart> parse(String body) {
    if (body.isEmpty) return const [];

    final matches = <_Match>[];

    for (final m in _urlRe.allMatches(body)) {
      final raw = _trimTrailingPunctuation(m.group(0)!);
      if (raw.isEmpty) continue;
      // A link that is really an email was matched by the domain rule.
      if (body.substring(0, m.start).endsWith('@')) continue;
      final value = raw.startsWith(RegExp(r'https?://', caseSensitive: false))
          ? raw
          : 'https://$raw';
      matches.add(
          _Match(m.start, m.start + raw.length, LinkKind.url, raw, value));
    }

    for (final m in _emailRe.allMatches(body)) {
      matches.add(_Match(m.start, m.end, LinkKind.email, m.group(0)!,
          'mailto:${m.group(0)}'));
    }

    for (final m in _phoneRe.allMatches(body)) {
      final raw = m.group(0)!;
      final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
      matches.add(
          _Match(m.start, m.end, LinkKind.phone, raw, 'tel:$digits'));
    }

    // Codes only count when the message says it is sending one. Without
    // that, every reference number and amount would look like an OTP.
    if (_codeContextRe.hasMatch(body)) {
      for (final m in _codeRe.allMatches(body)) {
        matches.add(_Match(
            m.start, m.end, LinkKind.code, m.group(0)!, m.group(0)!));
      }
    }

    return _assemble(body, matches);
  }

  /// True when the body carries something worth tapping.
  static bool hasLinks(String body) =>
      parse(body).any((p) => p.isLink);

  /// The one-time code in this message, if it has one. Offered as a copy
  /// action, since typing it from a notification is the usual chore.
  static String? code(String body) {
    for (final part in parse(body)) {
      if (part.kind == LinkKind.code) return part.text;
    }
    return null;
  }

  /// Earlier matches win, and a later one overlapping an accepted match is
  /// dropped. Order of the loops above is therefore the priority: a phone
  /// number inside a link stays part of the link.
  static List<MessagePart> _assemble(String body, List<_Match> matches) {
    matches.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : b.kind.index.compareTo(a.kind.index);
    });

    final parts = <MessagePart>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.start < cursor) continue;
      if (m.start > cursor) {
        parts.add(MessagePart.plain(body.substring(cursor, m.start)));
      }
      parts.add(MessagePart.link(m.text, m.kind, m.value));
      cursor = m.end;
    }
    if (cursor < body.length) {
      parts.add(MessagePart.plain(body.substring(cursor)));
    }
    return parts;
  }

  /// Sentences end in full stops and links do not, so trailing punctuation
  /// belongs to the sentence. Closing brackets are kept when the link opened
  /// one.
  static String _trimTrailingPunctuation(String url) {
    var end = url.length;
    while (end > 0) {
      final ch = url[end - 1];
      if ('.,;:!?'.contains(ch)) {
        end--;
      } else if (ch == ')' &&
          !url.substring(0, end).contains('(')) {
        end--;
      } else {
        break;
      }
    }
    return url.substring(0, end);
  }
}
