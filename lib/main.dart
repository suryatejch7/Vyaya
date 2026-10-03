import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
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

  // Initialize Notifications. A failure here mustn't keep the app from
  // opening (it would only mean no reminders).
  try {
    await NotificationService.initialize();
    await NotificationService.syncDailyReminder(
        AppPrefs.instance.reminderMinutes);
    await NotificationService.syncDetectedNotifier();
  } catch (e) {
    debugPrint('Notification setup failed: $e');
  }

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

  /// Why your data couldn't be opened, if it couldn't. Shows a recovery
  /// screen instead of spinning forever.
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_error != null) setState(() => _error = null);
    try {
      await _bootstrap();
    } catch (e, st) {
      debugPrint('Startup failed: $e\n$st');
      if (mounted) setState(() => _error = e);
    }
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
    } else {
      throw userProvider.errorMessage ?? 'Your account could not be loaded';
    }

    if (mounted) {
      setState(() => _ready = true);
    }
  }

  Future<void> _restoreBackup() async {
    String? path;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      path = result?.files.single.path;
    } catch (e) {
      debugPrint('Picking a backup failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t open the file. Try again.')),
        );
      }
      return;
    }
    if (path == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Restore Backup?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will replace ALL data on this phone with the data from the '
          'backup file.\n\nTap "Save a copy of my data" first if you might need what\'s '
          'here now. Continue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            child: const Text('Restore',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await BackupService.restoreFromFile(context, path);
    if (ok && mounted) await _start();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return _StartupProblem(
        error: error,
        onRetry: _start,
        onSaveCopy: () => BackupService.createAndShareBackup(context),
        onRestore: _restoreBackup,
      );
    }
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

/// Shown when the stored data can't be opened at start-up: try again, save
/// a copy of the raw data (so nothing is lost), or restore a backup.
class _StartupProblem extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onSaveCopy;
  final VoidCallback onRestore;
  const _StartupProblem({
    required this.error,
    required this.onRetry,
    required this.onSaveCopy,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Icon(Icons.error_outline_rounded,
                  color: Colors.orangeAccent, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Vyaya couldn\'t open your data',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Nothing has been deleted. Try again, or save a copy of your data first and then restore a backup.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  '$error',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onSaveCopy,
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('Save a copy of my data'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onRestore,
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Restore from a backup'),
              ),
            ],
          ),
        ),
      ),
    );
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
