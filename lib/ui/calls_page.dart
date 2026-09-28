import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/phone_service.dart';
import '../services/sms_service.dart';
import 'thread_page.dart';

final _timeFmt = DateFormat('d MMM, h:mm a');

/// Recent calls, and a keypad to make one.
class CallsPage extends ConsumerWidget {
  const CallsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calls = ref.watch(recentCallsProvider);
    final isDefault = ref.watch(isDefaultDialerProvider).valueOrNull ?? true;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openKeypad(context, ref),
        child: const Icon(Icons.dialpad),
      ),
      body: Column(
        children: [
          if (!isDefault)
            MaterialBanner(
              content: const Text(
                'Expense Tracker is not your default phone app, so incoming '
                'calls are handled elsewhere. Calls you make from here still '
                'work.',
              ),
              leading: const Icon(Icons.phone_disabled_outlined),
              actions: [
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(phoneServiceProvider)
                        .requestDefaultDialerRole();
                    ref.invalidate(isDefaultDialerProvider);
                    ref.invalidate(recentCallsProvider);
                  },
                  child: const Text('MAKE DEFAULT'),
                ),
              ],
            ),
          Expanded(
            child: calls.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return _Empty(
                    onGrant: () async {
                      await ref.read(phoneServiceProvider).requestPermissions();
                      ref.invalidate(recentCallsProvider);
                    },
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(recentCallsProvider),
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _CallTile(entry: list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openKeypad(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const _Keypad(),
      );
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
              Icon(Icons.call_outlined,
                  size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text('No recent calls',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Call history needs permission to read the phone log.',
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

class _CallTile extends ConsumerWidget {
  final CallEntry entry;
  const _CallTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // The log's cached name goes stale; the contact book is current.
    final name = entry.name ??
        ref.watch(contactNameProvider(entry.number)).valueOrNull;

    final (icon, color) = switch (entry.kind) {
      CallKind.incoming => (Icons.call_received, scheme.primary),
      CallKind.outgoing => (Icons.call_made, scheme.primary),
      CallKind.missed => (Icons.call_missed, scheme.error),
      CallKind.rejected => (Icons.call_end, scheme.error),
      CallKind.blocked => (Icons.block, scheme.error),
      CallKind.other => (Icons.call, scheme.outline),
    };

    final details = [
      _timeFmt.format(entry.at),
      if (entry.duration.inSeconds > 0) _duration(entry.duration),
    ].join(' · ');

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        name ?? (entry.number.isEmpty ? 'Unknown number' : entry.number),
        style: TextStyle(
          fontWeight: entry.isMissed ? FontWeight.w700 : FontWeight.w500,
          color: entry.isMissed ? scheme.error : null,
        ),
      ),
      subtitle: Text(details),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Message',
            icon: const Icon(Icons.sms_outlined),
            onPressed: entry.number.isEmpty
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ThreadPage(
                          sender: entry.number,
                          displayName: name ?? entry.number,
                        ),
                      ),
                    ),
          ),
          IconButton(
            tooltip: 'Call',
            icon: const Icon(Icons.call),
            onPressed: entry.number.isEmpty
                ? null
                : () => ref.read(phoneServiceProvider).call(entry.number),
          ),
        ],
      ),
    );
  }

  static String _duration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }
}

/// The dial pad. Plain digits, because a keypad that guesses is worse than
/// one that does not.
class _Keypad extends ConsumerStatefulWidget {
  const _Keypad();

  @override
  ConsumerState<_Keypad> createState() => _KeypadState();
}

class _KeypadState extends ConsumerState<_Keypad> {
  String _number = '';

  static const _keys = [
    ['1', ''],
    ['2', 'ABC'],
    ['3', 'DEF'],
    ['4', 'GHI'],
    ['5', 'JKL'],
    ['6', 'MNO'],
    ['7', 'PQRS'],
    ['8', 'TUV'],
    ['9', 'WXYZ'],
    ['*', ''],
    ['0', '+'],
    ['#', ''],
  ];

  @override
  Widget build(BuildContext context) {
    final name = _number.length >= 3
        ? ref.watch(contactNameProvider(_number)).valueOrNull
        : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 56,
              child: Center(
                child: Text(
                  _number.isEmpty ? 'Enter a number' : _number,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: _number.isEmpty
                            ? Theme.of(context).colorScheme.outline
                            : null,
                      ),
                ),
              ),
            ),
            if (name != null)
              Text(name, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            for (var row = 0; row < 4; row++)
              Row(
                children: [
                  for (var col = 0; col < 3; col++)
                    Expanded(
                      child: _Key(
                        digit: _keys[row * 3 + col][0],
                        letters: _keys[row * 3 + col][1],
                        onTap: () => setState(
                            () => _number += _keys[row * 3 + col][0]),
                        // Long-pressing zero is how a + is typed.
                        onLongPress: _keys[row * 3 + col][0] == '0'
                            ? () => setState(() => _number += '+')
                            : null,
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _number.isEmpty
                        ? null
                        : () async {
                            final phone = ref.read(phoneServiceProvider);
                            final navigator = Navigator.of(context);
                            await phone.call(_number);
                            navigator.pop();
                          },
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                  ),
                ),
                Expanded(
                  child: IconButton(
                    onPressed: _number.isEmpty
                        ? null
                        : () => setState(() => _number =
                            _number.substring(0, _number.length - 1)),
                    onLongPress: () => setState(() => _number = ''),
                    icon: const Icon(Icons.backspace_outlined),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final String digit;
  final String letters;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _Key({
    required this.digit,
    required this.letters,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(40),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Text(digit,
                  style: Theme.of(context).textTheme.headlineSmall),
              if (letters.isNotEmpty)
                Text(letters,
                    style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      );
}
