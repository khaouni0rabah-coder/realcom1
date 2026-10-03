import 'package:flutter/material.dart';

import 'core/auth/auth_session.dart';
import 'core/beast/beast_tracker.dart';
import 'core/beast/beast_user_session.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'screens/auth/account_switch_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  BeastUserSession.instance.attach();

  await ThemeController.instance.load();

  runApp(const WheelApp());
}

class WheelApp extends StatefulWidget {
  const WheelApp({super.key});

  @override
  State<WheelApp> createState() => _WheelAppState();
}

class _WheelAppState extends State<WheelApp> {
  final _themeController = ThemeController.instance;

  @override
  void initState() {
    super.initState();

    _themeController.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WeLibre',
      debugShowCheckedModeBanner: false,

      theme: AppTheme.light(),

      darkTheme: AppTheme.dark(),

      themeMode: _themeController.themeMode,

      // 🐺 تتبع تلقائي لكل تنقل بين الشاشات.
      navigatorObservers: [BeastTracker.instance.navigatorObserver],

      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthSession.instance,
      builder: (context, _) {
        if (AuthSession.instance.isAuthenticated) {
          return const HomeScreen();
        }

        return const AccountSwitchScreen();
      },
    );
  }
}
