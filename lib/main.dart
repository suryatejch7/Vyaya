import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/expense_provider.dart';
import 'providers/user_provider.dart';
import 'providers/capture_provider.dart';
import 'screens/main_screen.dart';
import 'services/local_store.dart';
import 'services/app_prefs.dart';
import 'services/backup_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/undo_bar.dart';
// import 'widgets/app_lock.dart'; // app lock switched off for now
import 'services/smart_notifications.dart';

/// System bars drawn over the app: see-through, light icons, and no grey or
/// white "contrast" scrim behind the 3-button navigation (the app's black
/// shows through instead, with a soft fade above it; see
/// [_SystemNavBarGuard]).
const _systemBars = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark, // iOS
  systemStatusBarContrastEnforced: false,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw behind the system bars on every Android version (Android 15 does
  // this anyway), so the bars look the same everywhere.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(_systemBars);

  // On-device storage (SharedPreferences)
  await LocalStore.initialize();
  await AppPrefs.instance.init();

  // Restore from auto-backup file if SharedPreferences was wiped
  await BackupService.restoreFromAutoBackupIfNeeded();

  // Initialize Notifications
  await NotificationService.initialize();
  await NotificationService.syncDailyReminder(AppPrefs.instance.reminderMinutes);
  await NotificationService.syncDetectedNotifier();

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
        // navigatorKey: appNavigatorKey,
        debugShowCheckedModeBanner: false,
        builder: (context, child) =>
            // App lock switched off for now:
            // _SystemNavBarGuard(child: LockGate(child: UndoHost(child: child!))),
            // The region keeps the bars see-through on every screen (an
            // AppBar only sets the status bar at the top).
            AnnotatedRegion<SystemUiOverlayStyle>(
              value: _systemBars,
              child: _SystemNavBarGuard(child: UndoHost(child: child!)),
            ),
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
      // Weekly summary / monthly recap / bill reminders stay up to date.
      SmartNotifications.attach(expenseProvider);
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
///
/// The buttons then sit on the app's own black (the system bar is
/// see-through), and a short gradient lets the app fade into it, like
/// Google Photos, instead of ending at a hard edge. Layout is unchanged:
/// nothing ends up under the buttons.
class _SystemNavBarGuard extends StatelessWidget {
  const _SystemNavBarGuard({required this.child});

  final Widget child;

  static const double _buttonNavThreshold = 32;

  /// Height of the fade above the buttons (short, so bottom bars and
  /// buttons near the edge stay readable).
  static const double _fadeHeight = 18;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final navInset = mq.viewPadding.bottom;

    // Gesture navigation: nothing to pad. The tree below stays the same
    // shape either way, so turning the phone (the button bar can move or
    // change size) never rebuilds the screens underneath.
    final buttons = navInset > _buttonNavThreshold;
    final inset = buttons ? navInset : 0.0;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: MediaQuery(
              data: !buttons ? mq : mq.copyWith(
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
          // Fade into the black behind the buttons. Taps go through.
          Positioned(
            left: 0,
            right: 0,
            bottom: inset,
            height: buttons ? _fadeHeight : 0,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00000000),
                      Color(0x33000000),
                      Color(0x99000000),
                    ],
                    stops: [0, 0.55, 1],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
