import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'auth.dart';
import 'l10n.dart';
import 'notifications.dart';
import 'screens/auth_screen.dart';
import 'screens/shell.dart';
import 'store.dart';
import 'sync.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('bn');
  await Notifier.init();
  await Store.instance.init();
  Notifier.onExactGranted = Store.instance.rescheduleAll;
  await AuthService.instance.init();
  await SyncService.instance.init();
  runApp(const BakiKhataApp());
}

class BakiKhataApp extends StatefulWidget {
  const BakiKhataApp({super.key});

  @override
  State<BakiKhataApp> createState() => _BakiKhataAppState();
}

class _BakiKhataAppState extends State<BakiKhataApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// অ্যাপে ফিরে এলে সিঙ্ক।
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) SyncService.instance.syncNow();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Store.instance.ledgerNotifier,
      builder: (context, ledger, _) => MaterialApp(
        title: 'Baki Khata',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, ledger),
        darkTheme: buildTheme(Brightness.dark, ledger),
        locale: const Locale('bn'),
        supportedLocales: const [Locale('bn'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        // ফোনে ২৪ ঘণ্টা চালু থাকলেও অ্যাপে সবসময় AM/PM
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        ),
        home: ListenableBuilder(
          listenable: AuthService.instance,
          builder: (_, _) => AuthService.instance.loggedIn
              ? const Shell()
              : const AuthScreen(),
        ),
      ),
    );
  }
}
