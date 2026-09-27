import 'dart:ui';
import 'package:flutter/material.dart';
import 'undo_snackbar.dart';

/// Hosts the undo pill above every screen. It sits exactly where the glass
/// nav bar is (the nav bar fades out while it shows), so on the home screen
/// it feels like the nav bar turning into an undo bar, the same way it turns
/// into Cancel / Delete in selection mode.
class UndoHost extends StatelessWidget {
  final Widget child;
  const UndoHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          // Stay above the keyboard when one is open.
          bottom: 30 + MediaQuery.of(context).viewInsets.bottom,
          child: ValueListenableBuilder<UndoRequest?>(
            valueListenable: UndoController.current,
            builder: (context, request, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.4),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: request == null
                  ? const SizedBox.shrink(key: ValueKey('no-undo'))
                  : Center(
                      key: ValueKey(request.id),
                      child: _UndoPill(request: request),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UndoPill extends StatefulWidget {
  final UndoRequest request;
  const _UndoPill({required this.request});

  @override
  State<_UndoPill> createState() => _UndoPillState();
}

class _UndoPillState extends State<_UndoPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdown =
      AnimationController(vsync: this, duration: UndoController.duration)
        ..forward();

  // Swipe down to dismiss early (the delete stays).
  double _dragDy = 0;
  bool _dragging = false;

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragging = true;
      _dragDy = (_dragDy + d.delta.dy).clamp(0.0, 120.0);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (_dragDy > 35 || velocity > 300) {
      UndoController.dismiss();
      return;
    }
    // Not far enough: spring back.
    setState(() {
      _dragging = false;
      _dragDy = 0;
    });
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    // Same glass styling and size as GlassNavBar (280x70 at 0.9 scale).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onVerticalDragCancel: () => setState(() {
        _dragging = false;
        _dragDy = 0;
      }),
      child: AnimatedContainer(
        duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _dragDy, 0),
        child: Opacity(
          opacity: (1 - _dragDy / 120).clamp(0.3, 1.0),
          child: _buildPill(primary),
        ),
      ),
    );
  }

  Widget _buildPill(Color primary) {
    return Transform.scale(
      scale: 0.9,
      child: Material(
        type: MaterialType.transparency,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(35),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              height: 70,
              width: 280,
              padding: const EdgeInsets.only(left: 22, right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(35),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.15),
                    Colors.white.withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded,
                      color: Colors.white.withValues(alpha: 0.8), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.request.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(25),
                    onTap: UndoController.undo,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Countdown ring: empties over the 5 seconds.
                          SizedBox(
                            width: 26,
                            height: 26,
                            child: AnimatedBuilder(
                              animation: _countdown,
                              builder: (context, _) => Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: 1 - _countdown.value,
                                    strokeWidth: 2.5,
                                    color: primary,
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.15),
                                  ),
                                  Icon(Icons.undo_rounded,
                                      size: 15, color: primary),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'UNDO',
                            style: TextStyle(
                              color: primary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
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
  }
}
