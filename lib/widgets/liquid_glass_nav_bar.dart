import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart' as vmath;
import '../models/quick_action_item.dart';
import '../widgets/glass_bottom_sheet.dart';
import 'undo_snackbar.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/analytics_screen.dart';
import 'package:provider/provider.dart';
import '../providers/capture_provider.dart';
import '../screens/detected_payments_screen.dart';
import '../screens/lent_borrowed_screen.dart';
import '../screens/recurring_screen.dart';
import '../services/app_prefs.dart';

class GlassNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final bool isSelectionMode;
  final int selectedCount;
  final VoidCallback? onClearSelection;
  final VoidCallback? onDeleteSelected;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isSelectionMode = false,
    this.selectedCount = 0,
    this.onClearSelection,
    this.onDeleteSelected,
  });

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar>
    with TickerProviderStateMixin {
  late AnimationController _pressController;
  late AnimationController _highlightController;
  late AnimationController _activeController;
  late AnimationController _swipeController;

  late Animation<double> _scaleAnimation;
  late Animation<double> _highlightAnimation;
  late Animation<double> _activeAnimation;
  late Animation<double> _swipeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _highlightController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _activeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _swipeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOutCubic),
    );

    _highlightAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _highlightController, curve: Curves.easeOut),
    );

    _activeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _activeController, curve: Curves.easeInOutCubic),
    );

    _swipeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _swipeController, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    _highlightController.dispose();
    _activeController.dispose();
    _swipeController.dispose();
    super.dispose();
  }

  void _onTapDown(int index) {
    _pressController.forward();
    _highlightController.forward();
  }

  void _onTapUp(int index) {
    _pressController.reverse();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _highlightController.reverse();
      }
    });

    widget.onTap(index);
  }

  void _onTapCancel() {
    _pressController.reverse();
    _highlightController.reverse();
  }

  void _showQuickActions() {
    final items = _getAllQuickActionItems();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => GlassBottomSheet(items: items),
    );
  }

  List<QuickActionItem> _getAllQuickActionItems() {
    return [
      QuickActionItem(
        id: 'analytics',
        icon: Icons.pie_chart_outline,
        title: 'Analytics',
        subtitle: 'View spending insights',
        color: Colors.purple,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AnalyticsScreen()),
          );
        },
      ),
      // Two of Detected Payments / Lent & Borrowed / Recurring, picked in
      // Settings → Optional features (the third is listed in Settings).
      for (final s in AppPrefs.instance.shortcutsInSheet) _shortcutItem(s),
      QuickActionItem(
        id: 'settings',
        icon: Icons.settings_outlined,
        title: 'Settings',
        subtitle: 'App preferences',
        color: Colors.grey,
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsScreen()),
          );
        },
      ),
    ];
  }

  void _openFromSheet(Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }

  QuickActionItem _shortcutItem(QuickShortcut s) {
    switch (s) {
      case QuickShortcut.detected:
        return QuickActionItem(
          id: 'detected',
          icon: Icons.bolt_rounded,
          title: 'Detected Payments',
          subtitle: switch (context.read<CaptureProvider>().pendingCount) {
            0 => 'From bank SMS & payment apps',
            1 => '1 waiting for review',
            final n => '$n waiting for review',
          },
          color: Colors.teal,
          onTap: () => _openFromSheet(const DetectedPaymentsScreen()),
        );
      case QuickShortcut.lentBorrowed:
        return QuickActionItem(
          id: 'lent_borrowed',
          icon: Icons.handshake_outlined,
          title: 'Lent & Borrowed',
          subtitle: 'Money with friends',
          color: Colors.amber,
          onTap: () => _openFromSheet(const LentBorrowedScreen()),
        );
      case QuickShortcut.recurring:
        return QuickActionItem(
          id: 'recurring',
          icon: Icons.repeat_rounded,
          title: 'Recurring',
          subtitle: 'Weekly, monthly or yearly',
          color: Colors.cyan,
          onTap: () => _openFromSheet(const RecurringScreen()),
        );
    }
  }

  void _handleHorizontalSwipe(DragEndDetails details) {
    const double swipeThreshold = 100.0;

    if (details.primaryVelocity!.abs() > swipeThreshold) {
      if (details.primaryVelocity! > 0) {
        // Swipe right: Home (0) → Categories (1)
        if (widget.currentIndex == 0) {
          _animateSwipeTransition(1);
        }
      } else {
        // Swipe left: Categories (1) → Home (0)
        if (widget.currentIndex == 1) {
          _animateSwipeTransition(0);
        }
      }
    }
  }

  void _animateSwipeTransition(int newIndex) {
    _swipeController.forward().then((_) {
      widget.onTap(newIndex);
      _swipeController.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Left-aligned so the + button (Home) or the filter button (Categories)
    // sits on the same row at the right.
    return Positioned(
      bottom: 30,
      left: 16,
      right: 0,
      child: ValueListenableBuilder<UndoRequest?>(
        valueListenable: UndoController.current,
        // Undo pill takes this spot for 5 s; fade the nav bar out meanwhile.
        builder: (context, undo, child) => AnimatedOpacity(
          opacity: undo == null ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(ignoring: undo != null, child: child),
        ),
        child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedBuilder(
          animation: Listenable.merge([_scaleAnimation, _swipeAnimation]),
          builder: (context, child) {
            return Transform.scale(
              alignment: Alignment.centerLeft, // keep the left edge fixed
              scale: _scaleAnimation.value * 0.9, // Scale down the nav bar
              child: GestureDetector(
                onHorizontalDragEnd: _handleHorizontalSwipe,
                // Swipe up anywhere on the bar -> quick actions sheet
                // (Analytics, two chosen shortcuts, Settings).
                onVerticalDragEnd: (details) {
                  if (widget.isSelectionMode) return;
                  final v = details.primaryVelocity;
                  if (v != null && v < -200) _showQuickActions();
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(35),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 70,
                      width: 280,
                      transform: Matrix4.identity()
                        ..setTranslationRaw(
                          _swipeAnimation.value *
                              10 *
                              (widget.currentIndex == 0 ? 1 : -1),
                          0,
                          0,
                        )
                        ..scaleByVector3(
                          vmath.Vector3.all(
                            1.0 + (_swipeAnimation.value * 0.015),
                          ),
                        ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(35),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(
                              alpha: 0.15 + (_swipeAnimation.value * 0.05),
                            ),
                            Colors.white.withValues(
                              alpha: 0.08 + (_swipeAnimation.value * 0.03),
                            ),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 20 + (_swipeAnimation.value * 10),
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 40 + (_swipeAnimation.value * 20),
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      // expand: the Row must fill the whole 280x70 bar (as it
                      // did before the handle was added) so items stay
                      // vertically centred; the handle only overlays.
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: widget.isSelectionMode
                            ? [
                                _buildSelectionNavItem(
                                  icon: Icons.close_rounded,
                                  label: 'Cancel',
                                  onTap: widget.onClearSelection,
                                ),
                                _buildSelectionCount(),
                                _buildSelectionNavItem(
                                  icon: Icons.delete_rounded,
                                  label: 'Delete',
                                  onTap: widget.onDeleteSelected,
                                  color: Colors.red,
                                ),
                              ]
                            : [
                                _buildNavItem(
                                  index: 0,
                                  icon: Icons.dashboard_rounded,
                                  activeIcon: Icons.dashboard,
                                  label: 'Home',
                                ),
                                _buildSearchNavItem(),
                                _buildNavItem(
                                  index: 1,
                                  icon: Icons.pie_chart_outline_rounded,
                                  activeIcon: Icons.pie_chart_rounded,
                                  label: 'Categories',
                                ),
                              ],
                      ),
                          // Grab handle: hints "swipe up for more"
                          if (!widget.isSelectionMode)
                            Positioned(
                              top: 4,
                              left: 0,
                              right: 0,
                              child: IgnorePointer(
                                child: Center(
                                  child: Container(
                                    width: 28,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: Colors.white
                                          .withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isActive = widget.currentIndex == index;

    return AnimatedBuilder(
      animation: Listenable.merge([_highlightAnimation, _activeAnimation]),
      builder: (context, child) {
        return GestureDetector(
          onTapDown: (_) => _onTapDown(index),
          onTapUp: (_) => _onTapUp(index),
          onTapCancel: _onTapCancel,
          child: Container(
            width: 80,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              color: isActive
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Icon(
                    isActive ? activeIcon : icon,
                    key: ValueKey(isActive),
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.7),
                    size: 24,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.7),
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Middle button: opens the Search screen (same one the sheet used to).
  Widget _buildSearchNavItem() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SearchScreen()),
      ),
      onLongPress: _showQuickActions, // backup for the swipe-up gesture
      child: Container(
        width: 80,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: Colors.transparent,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              color: Colors.white.withValues(alpha: 0.7),
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              'Search',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionNavItem({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? color,
  }) {
    final itemColor = color ?? Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          color: Colors.transparent,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: itemColor, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: itemColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionCount() {
    return Container(
      width: 80,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        color: Colors.white.withValues(alpha: 0.12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${widget.selectedCount}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          Text(
            'selected',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
