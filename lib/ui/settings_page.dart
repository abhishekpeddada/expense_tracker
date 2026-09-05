import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/openrouter.dart';
import '../services/settings_service.dart';
import 'backup_page.dart';
import 'diagnostics_page.dart';
import 'model_picker_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _key;
  bool _showKey = false;
  bool _testing = false;
  String? _testResult;
  bool _testFailed = false;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: ref.read(settingsProvider).openRouterKey);
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  void _saveKey() {
    ref.read(settingsProvider.notifier).setApiKey(_key.text);
    setState(() {
      _testResult = null;
      _testFailed = false;
    });
  }

  Future<void> _test() async {
    _saveKey();
    final client = ref.read(openRouterProvider);
    if (client == null) {
      setState(() {
        _testFailed = true;
        _testResult = 'Enter an API key first.';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    String message;
    var failed = false;
    try {
      message = await client.checkKey();
    } on OpenRouterException catch (e) {
      message = e.message;
      failed = true;
    } catch (e) {
      message = 'Could not reach OpenRouter: $e';
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = message;
      _testFailed = failed;
    });
  }

  Future<void> _pickModel() async {
    final settings = ref.read(settingsProvider);
    final picked = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ModelPickerPage(selected: settings.openRouterModel),
      ),
    );
    if (picked != null) {
      ref.read(settingsProvider.notifier).setModel(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final pitchBlack = settings.pitchBlack;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionHeader('Nutrition lookup'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'With an OpenRouter key, calories and macros are worked out '
              'automatically for whatever you log on the Food tab. Without '
              'one, the app falls back to its small built-in list of common '
              'foods.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _key,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'OpenRouter API key',
                hintText: 'sk-or-v1-...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _showKey ? 'Hide' : 'Show',
                  icon: Icon(_showKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onEditingComplete: _saveKey,
              onSubmitted: (_) => _saveKey(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                FilledButton.tonal(
                  onPressed: _testing ? null : _test,
                  child: _testing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save & test'),
                ),
                const SizedBox(width: 12),
                if (settings.hasKey)
                  TextButton(
                    onPressed: () {
                      _key.clear();
                      _saveKey();
                    },
                    child: const Text('Remove key'),
                  ),
              ],
            ),
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _testResult!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _testFailed
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'The key is stored on this device only. It is sent to '
              'openrouter.ai and nowhere else, and is left out of backup '
              'files. Only the food name and serving you type are sent for '
              'a lookup.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: const Text('Model'),
            subtitle: Text(settings.openRouterModel),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickModel,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Estimate automatically'),
            subtitle: const Text(
                'Look up calories as you type a food. Turn off to only '
                'estimate when you tap the button.'),
            value: settings.autoEstimate,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setAutoEstimate(v),
          ),
          const Divider(height: 32),
          const _SectionHeader('Appearance'),
          SwitchListTile(
            secondary: Icon(
                pitchBlack ? Icons.dark_mode : Icons.dark_mode_outlined),
            title: const Text('Pitch black theme'),
            subtitle: const Text('True black backgrounds, for OLED screens'),
            value: pitchBlack,
            onChanged: (_) =>
                ref.read(settingsProvider.notifier).togglePitchBlack(),
          ),
          const Divider(height: 32),
          const _SectionHeader('Data'),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Backup & restore'),
            subtitle: const Text('Export a snapshot, or restore one'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackupPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.health_and_safety_outlined),
            title: const Text('SMS diagnostics'),
            subtitle: const Text('Check why messages might not be arriving'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticsPage()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}
