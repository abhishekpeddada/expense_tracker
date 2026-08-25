import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/providers.dart';
import 'services/sms_service.dart';
import 'ui/accounts_page.dart';
import 'ui/diagnostics_page.dart';
import 'ui/dashboard_page.dart';
import 'ui/messages_page.dart';
import 'ui/transactions_page.dart';

/// True = force the pitch-black (AMOLED) dark theme; false = follow system.
final pitchBlackProvider =
    NotifierProvider<PitchBlackNotifier, bool>(PitchBlackNotifier.new);

class PitchBlackNotifier extends Notifier<bool> {
  static const _key = 'pitchBlack';

  @override
  bool build() => _prefs?.getBool(_key) ?? false;

  static SharedPreferences? _prefs;
  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  void toggle() {
    state = !state;
    _prefs?.setBool(_key, state);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PitchBlackNotifier.load();
  runApp(const ProviderScope(child: ExpenseTrackerApp()));
}

class ExpenseTrackerApp extends ConsumerWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const seed = Colors.teal;
    final pitchBlack = ref.watch(pitchBlackProvider);

    final darkScheme =
        ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    final amoled = ThemeData(
      useMaterial3: true,
      colorScheme: darkScheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF101010),
        surfaceContainerHigh: const Color(0xFF161616),
        surfaceContainerHighest: const Color(0xFF1C1C1C),
      ),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
      navigationBarTheme:
          const NavigationBarThemeData(backgroundColor: Colors.black),
    );

    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: pitchBlack
          ? amoled
          : ThemeData(colorScheme: darkScheme, useMaterial3: true),
      themeMode: pitchBlack ? ThemeMode.dark : ThemeMode.system,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;

  static const _titles = ['Messages', 'Transactions', 'Accounts', 'Dashboard'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final sms = ref.read(smsServiceProvider);
    sms.requestPermissions();
    sms.drainQueue();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(smsServiceProvider).drainQueue();
      ref.invalidate(isDefaultSmsAppProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uncategorized = ref.watch(uncategorizedProvider).valueOrNull ?? [];
    final pitchBlack = ref.watch(pitchBlackProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (_index == 0)
            IconButton(
              tooltip: 'SMS diagnostics',
              icon: const Icon(Icons.health_and_safety_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DiagnosticsPage()),
              ),
            ),
          IconButton(
            tooltip: pitchBlack ? 'Pitch black: on' : 'Pitch black: off',
            icon: Icon(
                pitchBlack ? Icons.dark_mode : Icons.dark_mode_outlined),
            onPressed: () =>
                ref.read(pitchBlackProvider.notifier).toggle(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          MessagesPage(),
          TransactionsPage(),
          AccountsPage(),
          DashboardPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: uncategorized.isNotEmpty,
              label: Text('${uncategorized.length}'),
              child: const Icon(Icons.receipt_long_outlined),
            ),
            selectedIcon: const Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance),
            label: 'Accounts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Dashboard',
          ),
        ],
      ),
    );
  }
}
