import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../services/backup_service.dart';

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(dbProvider)),
);

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backup = ref.read(backupServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Automatic backup is on. Android backs this app up to your '
              'Google Drive periodically while charging on Wi-Fi, and '
              'restores it when you reinstall the app or set up a new phone. '
              'It does not use your Drive storage quota.',
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Export backup file'),
            subtitle: const Text(
                'Save all transactions and messages as a file — send it to '
                'Google Drive or keep a copy anywhere'),
            enabled: !_busy,
            onTap: () => _run(backup.exportAndShare),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore from file'),
            subtitle: const Text(
                'Pick a previously exported backup; existing entries are '
                'kept and duplicates skipped'),
            enabled: !_busy,
            onTap: () => _run(() async {
              final messenger = ScaffoldMessenger.of(context);
              final r = await backup.importFromFile();
              messenger.showSnackBar(SnackBar(
                content: Text(
                  'Restored ${r.transactions} transactions and '
                  '${r.messages} messages'
                  '${r.skipped > 0 ? ' (${r.skipped} already present)' : ''}',
                ),
              ));
            }),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
