import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/expense_provider.dart';
import 'providers/user_provider.dart';
import 'providers/capture_provider.dart';
import 'screens/main_screen.dart';
import 'services/supabase_service.dart';
import 'services/backup_service.dart';
import 'services/notification_service.dart';
import 'services/cache_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Local Storage
  await ExpenseSupabaseService.initialize();

  // Restore from auto-backup file if SharedPreferences was wiped
  await BackupService.restoreFromAutoBackupIfNeeded();

  // Initialize Cache Service
  await CacheService.init();

  // Initialize Notifications
  await NotificationService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => CaptureProvider()),
      ],
      child: MaterialApp(
        title: 'Vyaya',
        theme: AppTheme.darkTheme,
        home: const AppBootstrap(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => _SystemNavBarGuard(child: child!),
      ),
    );
  }
}

/// Silently ensures a local user exists, then shows MainScreen.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final userProvider = context.read<UserProvider>();
    final expenseProvider = context.read<ExpenseProvider>();
    final captureProvider = context.read<CaptureProvider>();

    // Try to load existing user
    await userProvider.loadUserFromStorage();

    // No user selected (fresh install, or data restored from a backup /
    // auto-backup without the `userId` pref): adopt an existing user if the
    // storage has one, otherwise create the default local user.
    if (!userProvider.isLoggedIn) {
      final existing = await userProvider.getAllUsers();
      if (existing.isNotEmpty) {
        await userProvider.loginWithUserId(existing.first.id);
      } else {
        await userProvider.registerUser('LocalUser');
      }
    }

    // Initialize expense provider with the user
    if (userProvider.isLoggedIn) {
      await userProvider.initializeExpenseProvider(expenseProvider);
      // Payment auto-detection: drain anything captured while closed.
      await captureProvider.attach(expenseProvider);
    }

    if (mounted) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    return const MainScreen();
  }
}

/// Keeps the whole app (screens, bottom sheets, dialogs) above the Android
/// 3-button / 2-button navigation bar when running edge-to-edge.
///
/// Gesture navigation reports a small bottom inset (~16-24dp) and is left
/// untouched; button navigation reports ~48dp, so anything above the
/// threshold gets padded out and removed from the inner MediaQuery.
class _SystemNavBarGuard extends StatelessWidget {
  const _SystemNavBarGuard({required this.child});

  final Widget child;

  static const double _buttonNavThreshold = 32;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final navInset = mq.viewPadding.bottom;

    if (navInset <= _buttonNavThreshold) return child;

    return ColoredBox(
      color: Colors.black,
      child: Padding(
        padding: EdgeInsets.only(bottom: navInset),
        child: MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(bottom: 0),
            viewPadding: mq.viewPadding.copyWith(bottom: 0),
            // Keyboard inset is measured from the screen bottom; subtract the
            // nav bar we've already padded for so forms don't over-shift.
            viewInsets: mq.viewInsets.copyWith(
              bottom: math.max(0.0, mq.viewInsets.bottom - navInset),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
