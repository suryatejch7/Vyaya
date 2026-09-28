import 'package:flutter/material.dart';
import 'dart:math' as math;

/// iOS-like fluid animated expandable FAB for Add Expense/Income
class ExpandableFab extends StatefulWidget {
  final VoidCallback onAddExpense;
  final VoidCallback onAddIncome;
  final VoidCallback? onScanReceipt;

  /// Told when the menu opens or closes (the screen dims behind it).
  final ValueChanged<bool>? onOpenChanged;

  const ExpandableFab({
    super.key,
    required this.onAddExpense,
    required this.onAddIncome,
    this.onScanReceipt,
    this.onOpenChanged,
  });

  @override
  State<ExpandableFab> createState() => ExpandableFabState();
}

class ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotateAnimation;
  late Animation<double> _scaleAnimation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _rotateAnimation = Tween<double>(
      begin: 0.0,
      end: 0.125,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
    widget.onOpenChanged?.call(_isOpen);
  }

  /// Closes the menu (used by the screen when you tap outside it).
  void close() => _close();

  void _close() {
    if (_isOpen) {
      setState(() {
        _isOpen = false;
        _controller.reverse();
      });
      widget.onOpenChanged?.call(false);
    }
  }

  /// Instantly reset to closed state without animation (for navigation)
  void _closeInstant() {
    if (_isOpen) {
      setState(() {
        _isOpen = false;
        _controller.reset();
      });
      widget.onOpenChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Backdrop for dismissing
        if (_isOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),

        // Menu items
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Add Income button (Green) - positioned higher
            _buildMenuItem(
              index: 0,
              label: 'Add Income',
              icon: Icons.arrow_downward_rounded,
              color: Colors.green,
              onTap: () {
                _closeInstant();
                widget.onAddIncome();
              },
              offset: 140,
            ),

            // Add Expense button (Primary color)
            _buildMenuItem(
              index: 1,
              label: 'Add Expense',
              icon: Icons.arrow_upward_rounded,
              color: Theme.of(context).colorScheme.primary,
              onTap: () {
                _closeInstant();
                widget.onAddExpense();
              },
              offset: 70,
            ),

            // Main FAB
            _buildMainFab(context),
          ],
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required int index,
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required double offset,
  }) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Use controller.value (0-1) for the interval, then apply easing
        final intervalValue = Interval(
          0.0 + (index * 0.1),
          0.8 + (index * 0.1),
          curve: Curves.easeOutCubic,
        ).transform(_controller.value.clamp(0.0, 1.0));

        // Apply spring-like overshoot manually for fluid feel
        final springValue =
            intervalValue + (0.1 * math.sin(intervalValue * math.pi));

        return Transform.translate(
          offset: Offset(0, offset * (1 - intervalValue)),
          child: Opacity(
            opacity: intervalValue.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.5 + (0.5 * springValue.clamp(0.0, 1.1)),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Label with glass effect
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade900.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Mini FAB
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainFab(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Transform.rotate(
              angle: _rotateAnimation.value * 2 * math.pi,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isOpen
                        ? [Colors.grey.shade700, Colors.grey.shade800]
                        : [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.8),
                          ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_isOpen
                                  ? Colors.grey
                                  : Theme.of(context).colorScheme.primary)
                              .withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Icon(
                    _isOpen ? Icons.close : Icons.add,
                    key: ValueKey(_isOpen),
                    color: _isOpen ? Colors.white : Colors.black,
                    size: 28,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Helper widget for animated builder with child
class AnimatedBuilder extends StatelessWidget {
  final Animation<double> animation;
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder2(
      animation: animation,
      builder: builder,
      child: child,
    );
  }
}

class AnimatedBuilder2 extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder2({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
