import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:expense_tracker/data/db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDb db;
  setUp(() => db = AppDb.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> incoming(String sender, String body, DateTime at,
          {bool read = false}) =>
      db.insertMessage(SmsMessagesCompanion.insert(
        sender: sender,
        body: body,
        receivedAt: at,
        read: Value(read),
      ));

  Future<int> outgoing(String sender, String body, DateTime at) =>
      db.insertMessage(SmsMessagesCompanion.insert(
        sender: sender,
        body: body,
        receivedAt: at,
        outgoing: const Value(true),
        read: const Value(true),
      ));

  Future<List<SmsMessage>> all() => db.watchMessages().first;
  Future<int> unreadCount() async =>
      (await all()).where((m) => !m.read && !m.outgoing).length;

  group('marking several conversations read', () {
    setUp(() async {
      await incoming('HDFC', 'debited 100', DateTime(2026, 9, 1));
      await incoming('HDFC', 'debited 200', DateTime(2026, 9, 2));
      await incoming('ICICI', 'credited 500', DateTime(2026, 9, 3));
      await incoming('Mum', 'call me', DateTime(2026, 9, 4));
    });

    test('clears unread across every selected sender', () async {
      final changed = await db.markThreadsRead(['HDFC', 'ICICI']);
      expect(changed, 3);

      final remaining = (await all()).where((m) => !m.read).map((m) => m.sender);
      expect(remaining, ['Mum']);
    });

    test('counts only what it actually changed', () async {
      await db.markThreadsRead(['HDFC']);
      expect(await db.markThreadsRead(['HDFC']), 0);
    });

    test('an empty selection does nothing', () async {
      expect(await db.markThreadsRead([]), 0);
      expect(await unreadCount(), 4);
    });

    test('mark all read leaves nothing unread', () async {
      expect(await db.markAllRead(), 4);
      expect(await unreadCount(), 0);
    });

    test('outgoing messages are never counted as unread work', () async {
      await outgoing('Mum', 'on my way', DateTime(2026, 9, 5));
      expect(await db.markThreadsRead(['Mum']), 1);
      expect(await unreadCount(), 3);
    });
  });

  group('marking several conversations unread', () {
    test('puts back exactly one message per conversation', () async {
      await incoming('HDFC', 'older', DateTime(2026, 9, 1), read: true);
      await incoming('HDFC', 'newest', DateTime(2026, 9, 2), read: true);
      await incoming('ICICI', 'only', DateTime(2026, 9, 3), read: true);

      await db.markThreadsUnread(['HDFC', 'ICICI']);

      final unread =
          (await all()).where((m) => !m.read).map((m) => m.body).toList();
      expect(unread, containsAll(['newest', 'only']));
      expect(unread, hasLength(2));
    });

    test('a conversation with only outgoing messages is left alone',
        () async {
      await outgoing('Mum', 'hello', DateTime(2026, 9, 1));
      await db.markThreadsUnread(['Mum']);
      expect(await unreadCount(), 0);
    });
  });

  group('deleting several conversations', () {
    test('removes every message from the selected senders', () async {
      await incoming('HDFC', 'a', DateTime(2026, 9, 1));
      await incoming('HDFC', 'b', DateTime(2026, 9, 2));
      await incoming('Mum', 'c', DateTime(2026, 9, 3));

      await db.deleteThreads(['HDFC']);

      final left = await all();
      expect(left.map((m) => m.sender), ['Mum']);
    });

    test('an empty selection deletes nothing', () async {
      await incoming('HDFC', 'a', DateTime(2026, 9, 1));
      await db.deleteThreads([]);
      expect(await all(), hasLength(1));
    });
  });
}
