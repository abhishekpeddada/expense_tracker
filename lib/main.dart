import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers.dart';
import 'services/budget_alerts.dart';
import 'services/phone_service.dart';
import 'services/self_transfer.dart';
import 'services/settings_service.dart';
import 'services/sms_service.dart';
import 'services/chat_service.dart';
import 'services/receipt_import.dart';
import 'ui/accounts_page.dart';
import 'ui/chat_page.dart';
import 'ui/diagnostics_page.dart';
import 'ui/dashboard_page.dart';
import 'ui/food_page.dart';
import 'ui/inbox_page.dart';
import 'ui/receipt_import_page.dart';
import 'ui/settings_page.dart';
import 'ui/transactions_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsNotifier.load();
  runApp(const ProviderScope(child: ExpenseTrackerApp()));
}

class ExpenseTrackerApp extends ConsumerWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const seed = Colors.teal;
    final pitchBlack = ref.watch(settingsProvider).pitchBlack;

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

  static const _titles = [
    'Messages & calls',
    'Transactions',
    'Food',
    'Assistant',
    'Accounts',
    'Dashboard',
  ];

  /// Index of the Chat tab, which brings its own app-bar actions.
  static const _chatIndex = 3;

  /// Guards against opening two receipt screens when a share arrives at the
  /// same moment as a resume.
  bool _readingReceipt = false;

  /// Held rather than read back out of [ref] later: the shell is torn down
  /// with the app, by which point reading a provider is no longer allowed.
  late final SmsService _sms;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sms = ref.read(smsServiceProvider);
    _sms.requestPermissions();
    _sms.drainQueue();
    _sms.onSharedImage = _openSharedReceipt;
    // Only meaningful once the dialer role is held; harmless before then,
    // and the call log needs the permission either way.
    ref.read(phoneServiceProvider).requestPermissions();
    _catchUp();
    // After the first frame, so there is a Navigator to push onto.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _openSharedReceipt());
  }

  /// Picks up an image shared in from a payment app. The native side holds
  /// it until it is collected, so this works whether the share launched the
  /// app cold or landed on it already running.
  Future<void> _openSharedReceipt() async {
    if (_readingReceipt) return;
    _readingReceipt = true;
    try {
      final image = await ref.read(receiptImportProvider).takeShared();
      if (image == null || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReceiptImportPage(image: image)),
      );
    } finally {
      _readingReceipt = false;
    }
  }

  /// Housekeeping that runs whenever the app comes to the front: pair up
  /// self transfers before budgets are checked, so money moved between the
  /// user's own accounts never counts towards a budget.
  Future<void> _catchUp() async {
    final db = ref.read(dbProvider);
    await SelfTransfers.apply(db);
    await BudgetAlerts(db).check();
  }

  @override
  void dispose() {
    _sms.onSharedImage = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(smsServiceProvider).drainQueue();
      ref.invalidate(isDefaultSmsAppProvider);
      _catchUp();
      _openSharedReceipt();
    }
  }

  Future<void> _confirmClearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
            'The whole thread is deleted. Your transactions and food log '
            'are not affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CLEAR'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(chatServiceProvider).clear();
  }

  @override
  Widget build(BuildContext context) {
    final uncategorized = ref.watch(uncategorizedProvider).valueOrNull ?? [];

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
          if (_index == _chatIndex)
            PopupMenuButton<String>(
              tooltip: 'Chat options',
              onSelected: (value) {
                switch (value) {
                  case 'context':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ChatContextPage()),
                    );
                  case 'clear':
                    _confirmClearChat();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'context',
                  child: Text('What gets sent'),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: Text('Clear conversation'),
                ),
              ],
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          InboxPage(),
          TransactionsPage(),
          FoodPage(),
          ChatPage(),
          AccountsPage(),
          DashboardPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        // Six destinations is more than the labels fit side by side, so
        // only the selected one is named.
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
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
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Food',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Assistant',
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
