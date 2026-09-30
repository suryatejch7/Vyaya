import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dashboard_screen.dart';
import 'categories_screen.dart';
import 'add_expense_screen.dart';
import 'add_income_screen.dart';
// Screenshot scanning is disabled (offline build) - see README.md.
// import 'transaction_scanner_screen.dart';
// import '../services/sharing_intent_service.dart';
import '../services/intent_service.dart';
import '../services/local_store.dart';
import '../services/backup_service.dart';
import '../services/smart_notifications.dart';
import '../widgets/liquid_glass_nav_bar.dart';
import '../widgets/expandable_fab.dart';
import '../providers/expense_provider.dart';
import '../providers/capture_provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _fabOpen = false;
  final _fabKey = GlobalKey<ExpandableFabState>();
  bool _isSelectionMode = false;
  int _selectedCount = 0;
  VoidCallback? _clearSelection;
  VoidCallback? _deleteSelected;

  final List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _screens.addAll([
      DashboardScreen(
        onSelectionChanged:
            (isSelectionMode, selectedCount, clearSelection, deleteSelected) {
              setState(() {
                _isSelectionMode = isSelectionMode;
                _selectedCount = selectedCount;
                _clearSelection = clearSelection;
                _deleteSelected = deleteSelected;
              });
            },
      ),
      const CategoriesScreen(),
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // SharingIntentService.setContext(context); // screenshot scanning off
      IntentService.setContext(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When the app comes back to the foreground (possibly on a new day or
  /// month), create any recurring entries that became due and close out
  /// finished months into "Saved".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app: write any changes still waiting (saves are grouped
    // for a moment) so nothing is lost if Android closes the app.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      LocalStore.flush().then((_) => BackupService.flushPending());
    }
    if (state == AppLifecycleState.resumed && mounted) {
      // Re-plan summaries/reminders (the weekly one is scheduled a week at
      // a time).
      SmartNotifications.sync();
      context.read<ExpenseProvider>().runAutomations();
      // Pick up payments captured in the background + permission changes
      // made in system settings.
      context.read<CaptureProvider>()
        ..refreshStatus()
        ..sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Back: first leaves selection mode, then returns to Home from another
    // tab, and only exits the app from Home.
    return PopScope(
      canPop: !_isSelectionMode && _currentIndex == 0 && !_fabOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_fabOpen) {
          _fabKey.currentState?.close();
        } else if (_isSelectionMode) {
          _clearSelection?.call();
        } else if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Container(color: Colors.black),
          // Both tabs stay alive, so Home keeps its scroll position and
          // doesn't rebuild (or replay its animations) on every switch.
          // _screens[_currentIndex],
          IndexedStack(index: _currentIndex, children: _screens),
          GlassNavBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              if (index != _currentIndex) {
                // Leaving Home ends a selection first; Home's selection
                // state goes away with the tab.
                if (_isSelectionMode) _clearSelection?.call();
                setState(() {
                  _currentIndex = index;
                  _isSelectionMode = false;
                  _selectedCount = 0;
                });
              }
            },
            isSelectionMode: _isSelectionMode,
            selectedCount: _selectedCount,
            onClearSelection: _clearSelection,
            onDeleteSelected: _deleteSelected,
          ),
          // While the + menu is open, a tap anywhere outside it closes it
          // instead of reaching the list. (No dimming; to dim the screen,
          // swap the SizedBox for the commented ColoredBox.)
          if (_fabOpen && _currentIndex == 0)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _fabKey.currentState?.close(),
                child: const SizedBox.expand(),
                // child: const ColoredBox(color: Color(0x66000000)),
              ),
            ),
          // On the nav bar's row, at the right (centred on the bar's height).
          // Hidden while selecting, when the bar becomes Cancel / Delete.
          if (_currentIndex == 0 && !_isSelectionMode)
            Positioned(
              right: 16,
              bottom: 37,
              child: ExpandableFab(
                key: _fabKey,
                onOpenChanged: (open) => setState(() => _fabOpen = open),
                onAddExpense: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddExpenseScreen(),
                    ),
                  );
                },
                onAddIncome: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddIncomeScreen(),
                    ),
                  );
                },
                // Screenshot scanning is disabled (offline build).
                // onScanReceipt: () {
                //   Navigator.push(
                //     context,
                //     MaterialPageRoute(
                //       builder: (context) => const TransactionScannerScreen(),
                //     ),
                //   );
                // },
              ),
            ),
        ],
      ),
    ),
    );
  }
}
