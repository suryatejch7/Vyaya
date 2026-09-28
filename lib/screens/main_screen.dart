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
    if (state == AppLifecycleState.resumed && mounted) {
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
      canPop: !_isSelectionMode && _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSelectionMode) {
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
          _screens[_currentIndex],
          GlassNavBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              if (index != _currentIndex) {
                setState(() {
                  _currentIndex = index;
                });
              }
            },
            isSelectionMode: _isSelectionMode,
            selectedCount: _selectedCount,
            onClearSelection: _clearSelection,
            onDeleteSelected: _deleteSelected,
          ),
          if (_currentIndex == 0)
            Positioned(
              right: 16,
              bottom: 120,
              child: ExpandableFab(
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
