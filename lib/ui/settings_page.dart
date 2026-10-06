import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/card_cycle.dart';
import '../services/openrouter.dart';
import '../services/phone_service.dart';
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

    // Two separate things can be wrong: the key, or the chosen model. The
    // key check alone would pass while every lookup still failed, so this
    // runs a real estimate through the selected model as well.
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

    if (!failed) {
      try {
        final e = await client.estimate(_testFood);
        final kcal = e.calories;
        message = '$message\n\n${client.model} answered for $_testFood: '
            '${kcal == null ? 'no calorie figure' : '${kcal.round()} kcal'}'
            '${e.hasMacros ? ', with macros' : ', no macros'}.';
      } on OpenRouterException catch (e) {
        failed = true;
        message = 'The key works, but ${client.model} could not answer: '
            '${e.message}';
      } catch (e) {
        failed = true;
        message = 'The key works, but the lookup failed: $e';
      }
    }

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = message;
      _testFailed = failed;
    });
  }

  /// A food deliberately not in the built-in list, so the test cannot pass
  /// on a local answer while the model is actually broken.
  static const _testFood = 'Ragi mudde with bassaru';

  Future<void> _pickModel() async {
    final settings = ref.read(settingsProvider);
    final picked = await Navigator.push<ModelChoice>(
      context,
      MaterialPageRoute(
        builder: (_) => ModelPickerPage(selected: settings.openRouterModel),
      ),
    );
    if (picked != null) {
      ref
          .read(settingsProvider.notifier)
          .setModel(picked.id, acceptsImages: picked.acceptsImages);
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
          const _SectionHeader('OpenRouter'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'One key powers three things: calories and macros worked out '
              'automatically for whatever you log on the Food tab, logging '
              'a whole plate from a photo, and the Assistant tab, where you '
              'can ask questions about your own spending and eating. '
              'Photos need a model that reads images - those are marked '
              'with a camera in the picker. Without a key, food logging '
              'falls back to a small built-in list.',
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
                      : const Text('Save & test lookup'),
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
              'files. A food lookup sends just the name and serving you '
              'typed, and a photo lookup sends the downscaled picture. '
              'The Assistant sends a summary of your transactions, '
              'accounts, budgets and food log — never raw SMS text — and '
              '"What gets sent" on that tab shows it in full.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: const Text('Model'),
            subtitle: Text('${settings.openRouterModel}\n'
                '${switch (settings.modelAcceptsImages) {
              true => 'Reads photos. Used for food lookups, photo logging '
                  'and the Assistant',
              false => 'Cannot read photos - pick a vision model for photo '
                  'logging',
              null => 'Used for food lookups and the Assistant',
            }}'),
            isThreeLine: true,
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
          const _SectionHeader('Credit card'),
          const _CardCycleSettings(),
          const Divider(height: 32),
          const _SectionHeader('Phone'),
          const _DialerRole(),
          const _FullScreenCalls(),
          const _VoicemailNumber(),
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

/// When the card statement closes, and when its bill is paid.
///
/// Card spending is billed in statement periods, not calendar months: a
/// purchase on the 28th is on next month's bill. Without these two days
/// the dashboard has to guess, and guessing splits one bill across two
/// months so neither figure matches the statement.
class _CardCycleSettings extends ConsumerWidget {
  const _CardCycleSettings();

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    return switch (day % 10) {
      1 => '${day}st',
      2 => '${day}nd',
      3 => '${day}rd',
      _ => '${day}th',
    };
  }

  Future<void> _pickDay(
    BuildContext context, {
    required String title,
    required String? monthlyOption,
    required int selected,
    required ValueChanged<int> onPicked,
  }) async {
    final day = await showDialog<int>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(title),
          // Scrollable so the grid still reaches its last row in
          // landscape, where the dialog has little height to work with.
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A calendar-shaped grid rather than a list of 28 rows: the
              // day being picked is a date, and this way it is all on
              // screen at once.
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  // 28 is the last day every month has. Past it the
                  // boundary would move around, so a card billed later is
                  // treated as calendar-month billed instead.
                  for (var d = 1; d <= CardCycle.maxDay; d++)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Material(
                        color: d == selected
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.pop(context, d),
                          child: Center(
                            child: Text(
                              '$d',
                              style: TextStyle(
                                color: d == selected
                                    ? scheme.onPrimary
                                    : scheme.onSurfaceVariant,
                                fontWeight: d == selected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (monthlyOption != null) ...[
                const SizedBox(height: 8),
                if (selected == 0)
                  FilledButton.tonal(
                    onPressed: () => Navigator.pop(context, 0),
                    child: Text(monthlyOption),
                  )
                else
                  TextButton(
                    onPressed: () => Navigator.pop(context, 0),
                    child: Text(monthlyOption),
                  ),
              ],
            ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
          ],
        );
      },
    );
    if (day != null) onPicked(day);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final cycle = settings.cardCycle;
    final current = cycle.current;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.event_available_outlined),
          title: const Text('Statement closes'),
          subtitle: Text(cycle.isCalendarMonth
              ? 'On the last day of the month'
              : 'On the ${_ordinal(settings.cardStatementDay)} of every '
                  'month'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickDay(
            context,
            title: 'Statement closes on',
            monthlyOption: 'Last day of the month',
            selected: settings.cardStatementDay,
            onPicked: notifier.setCardStatementDay,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: const Text('Bill paid'),
          subtitle:
              Text('On the ${_ordinal(settings.cardDueDay)} after the '
                  'statement closes'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pickDay(
            context,
            title: 'Bill paid on',
            monthlyOption: null,
            selected: settings.cardDueDay,
            onPicked: notifier.setCardDueDay,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Card spending on the dashboard is counted over the statement '
            'period, not the calendar month. The period open now is '
            '${current.label}, and its bill is due ${current.dueLabel}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Whether the incoming call screen may take over the display.
///
/// Android 14 put full-screen intents behind their own permission. Calling
/// apps get it at install, but it can be revoked, and when it is the
/// incoming call screen silently becomes a heads-up notification with
/// nothing to say why. Worth stating plainly rather than leaving the user
/// to guess at a phone that no longer rings properly.
class _FullScreenCalls extends ConsumerWidget {
  const _FullScreenCalls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed =
        ref.watch(canUseFullScreenIntentProvider).valueOrNull ?? true;
    if (allowed) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.fullscreen_exit, color: scheme.onErrorContainer),
        title: const Text('Incoming calls cannot take over the screen'),
        subtitle: const Text(
            'Android is holding back the full-screen permission, so calls '
            'arrive as a notification instead of the call screen. Tap to '
            'allow it.'),
        onTap: () async {
          await ref.read(phoneServiceProvider).openFullScreenIntentSettings();
          ref.invalidate(canUseFullScreenIntentProvider);
        },
      ),
    );
  }
}

/// Override for the voicemail number.
///
/// Worth having because the SIM field is not reliable: some Indian
/// carriers leave it empty, and some store the subscriber's own number in
/// it, which makes "call voicemail" dial you.
class _VoicemailNumber extends ConsumerStatefulWidget {
  const _VoicemailNumber();

  @override
  ConsumerState<_VoicemailNumber> createState() => _VoicemailNumberState();
}

class _VoicemailNumberState extends ConsumerState<_VoicemailNumber> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(settingsProvider).voicemailNumber);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(settingsProvider.notifier).setVoicemailNumber(_controller.text);
    ref.invalidate(voicemailProvider);
  }

  @override
  Widget build(BuildContext context) {
    final sim = ref.watch(voicemailProvider).valueOrNull;
    final fromSim = sim != null && !sim.isOverride ? sim.number : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Voicemail number',
              hintText: fromSim ?? 'Leave empty to use the SIM',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: 'Save',
                icon: const Icon(Icons.check),
                onPressed: _save,
              ),
            ),
            onEditingComplete: _save,
            onSubmitted: (_) => _save(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              fromSim == null
                  ? 'Your SIM reports no voicemail number. Enter your '
                      'carrier\'s one here.'
                  : 'Your SIM reports $fromSim. If that is your own number '
                      'rather than the voicemail service, enter the right '
                      'one here.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Taking over the phone role, with what it actually means spelled out.
class _DialerRole extends ConsumerWidget {
  const _DialerRole();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDefault = ref.watch(isDefaultDialerProvider).valueOrNull ?? false;
    final phone = ref.read(phoneServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(isDefault ? Icons.phone_enabled : Icons.phone_outlined),
          title: Text(isDefault
              ? 'This is your default phone app'
              : 'Set as default phone app'),
          subtitle: Text(isDefault
              ? 'Incoming calls ring here and the dial pad places calls'
              : 'Calls from the Calls tab already work. Take this on and '
                  'incoming calls ring here too.'),
          trailing: isDefault ? null : const Icon(Icons.chevron_right),
          onTap: isDefault
              ? null
              : () async {
                  await phone.requestPermissions();
                  await phone.requestDefaultDialerRole();
                  ref.invalidate(isDefaultDialerProvider);
                },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            isDefault
                ? 'If a call ever fails to ring properly, hand the role back '
                    'to your old phone app in Android Settings > Default '
                    'apps. Nothing else in this app depends on it.'
                : 'Keep your old phone app installed. Handing the role back '
                    'in Android Settings takes a few seconds if anything '
                    'misbehaves.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
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
