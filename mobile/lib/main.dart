import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'notifications.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: C.bg2,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  try {
    await Reminders.instance.init();
  } catch (_) {
    // Без уведомлений приложение всё равно должно работать.
  }
  final store = AppStore();
  await store.init();
  runApp(ScopeApp(store: store));
}

class ScopeApp extends StatelessWidget {
  const ScopeApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: MaterialApp(
        title: 'Scope',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: store.loggedIn ? const HomeShell(key: ValueKey('home')) : const LoginScreen(key: ValueKey('login')),
    );
  }
}
