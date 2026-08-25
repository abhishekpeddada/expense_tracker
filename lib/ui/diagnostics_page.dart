import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/sms_service.dart';

final _fmt = DateFormat('d MMM, h:mm:ss a');

/// Shows whether the app is actually set up to receive SMS, and a log of
/// what the broadcast receiver saw. Lets reception problems be diagnosed
/// on-device instead of needing adb.
class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  Map<String, bool> _checks = {};
  List<Map<String, Object?>> _log = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final sms = ref.read(smsServiceProvider);
    final checks = await sms.diagnostics();
    final log = await sms.receiveLog();
    if (!mounted) return;
    setState(() {
      _checks = checks;
      _log = log;
      _loading = false;
    });
  }

  static const _labels = {
    'isDefaultSmsApp': 'Default SMS app',
    'batteryUnrestricted': 'Battery unrestricted',
    'receiveSms': 'Receive SMS permission',
    'readSms': 'Read SMS permission',
    'notifications': 'Notification permission',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          IconButton(
            tooltip: 'Copy log',
            icon: const Icon(Icons.copy_all),
            onPressed: () {
              final text = [
                for (final e in _checks.entries) '${e.key}: ${e.value}',
                '---',
                for (final e in _log)
                  '${_fmt.format(DateTime.fromMillisecondsSinceEpoch(
                      (e['ts'] as num).toInt()))}  ${e['message']}',
              ].join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Diagnostics copied')));
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                for (final entry in _labels.entries)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      (_checks[entry.key] ?? false)
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: (_checks[entry.key] ?? false)
                          ? Colors.green
                          : scheme.error,
                    ),
                    title: Text(entry.value),
                    subtitle: (_checks[entry.key] ?? false)
                        ? null
                        : const Text('Not granted — messages may be missed'),
                  ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Received messages log',
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      TextButton(
                        onPressed: () async {
                          await ref.read(smsServiceProvider).clearReceiveLog();
                          _refresh();
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
                if (_log.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Nothing logged yet. If a message arrived in another '
                      'SMS app but nothing appears here, this app never '
                      'received the broadcast.',
                    ),
                  ),
                for (final e in _log)
                  ListTile(
                    dense: true,
                    title: Text('${e['message']}'),
                    subtitle: Text(_fmt.format(
                        DateTime.fromMillisecondsSinceEpoch(
                            (e['ts'] as num).toInt()))),
                  ),
              ],
            ),
    );
  }
}
