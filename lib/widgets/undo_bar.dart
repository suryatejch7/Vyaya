import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'undo_snackbar.dart';

/// How much the 280-wide glass bars (nav bar, undo bar) are scaled: 0.9
/// normally, smaller on narrow phones (320 dp) so they never run into the
/// round + / filter button at the right of their row (16 dp margins, 56 dp
/// button, 8 dp gap).
double glassBarScale(BuildContext context) {
  final room = MediaQuery.of(context).size.width - 96;
  return (room / 280).clamp(0.6, 0.9);
}

/// Hosts the undo dock above every screen.
///
/// Full bar: sits exactly where the glass nav bar is (the nav bar fades out
/// while it shows), so on Home it feels like the nav bar turning into an
/// undo bar. Bubble: when a second action comes in, the bar shrinks into a
/// small round bubble that floats just above the nav bar, with a countdown
/// ring and a count. Tap it to open the bar again.
class UndoHost extends StatelessWidget {
  final Widget child;
  const UndoHost({super.key, required this.child});

  /// How far the bubble floats above the bar's spot (clears the nav bar).
  static const double bubbleRise = 74;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        ValueListenableBuilder<double>(
          valueListenable: UndoController.lift,
          builder: (context, lift, _) => ValueListenableBuilder<UndoState>(
            valueListenable: UndoController.state,
            builder: (context, state, _) => AnimatedPositioned(
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutCubic,
              left: 16,
              right: 0,
              // Stay above the keyboard (and any bottom bar) when one is open.
              bottom: 30 +
                  keyboard +
                  lift +
                  (state.collapsed ? bubbleRise : 0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                // What's fading out can't be tapped (its UNDO would hit a
                // different action).
                layoutBuilder: _fadeOutIgnored,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    alignment: Alignment.centerLeft,
                    scale: Tween<double>(begin: 0.85, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: state.items.isEmpty
                    ? const SizedBox.shrink(key: ValueKey('no-undo'))
                    : Align(
                        key: const ValueKey('undo-dock'),
                        alignment: Alignment.centerLeft,
                        // Fixed-size bar: text grows up to 1.3x, like the
                        // nav bar.
                        child: MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.3,
                          child: _UndoDock(state: state),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// AnimatedSwitcher layout where the outgoing child ignores taps.
Widget _fadeOutIgnored(Widget? current, List<Widget> previous) => Stack(
      alignment: Alignment.center,
      children: [
        for (final p in previous) IgnorePointer(child: p),
        if (current != null) current,
      ],
    );

class _UndoDock extends StatefulWidget {
  final UndoState state;
  const _UndoDock({required this.state});

  @override
  State<_UndoDock> createState() => _UndoDockState();
}

class _UndoDockState extends State<_UndoDock>
    with SingleTickerProviderStateMixin {
  // Empties over the 5 seconds; starts over whenever the time does.
  late final AnimationController _countdown =
      AnimationController(vsync: this, duration: UndoController.duration)
        ..forward();

  // Swipe down to close early (the actions stay done).
  double _dragDy = 0;
  bool _dragging = false;

  static const _morph = Duration(milliseconds: 340);

  @override
  void didUpdateWidget(_UndoDock old) {
    super.didUpdateWidget(old);
    if (widget.state.round != old.state.round) _countdown.forward(from: 0);
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

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
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final collapsed = widget.state.collapsed;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: collapsed
          ? () {
              HapticFeedback.selectionClick();
              UndoController.expand();
            }
          : null,
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
          // Same glass styling and size as GlassNavBar (280x70, scaled).
          child: Transform.scale(
            alignment: Alignment.centerLeft,
            scale: glassBarScale(context),
            child: Semantics(
              button: collapsed,
              label: collapsed
                  ? 'Undo, ${widget.state.count} actions. Tap to open'
                  : null,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _glass(collapsed, primary),
                  // How many actions can still be undone.
                  Positioned(
                    top: -4,
                    right: -4,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: a, child: c),
                      child: collapsed && widget.state.count > 1
                          ? _Badge(
                              key: ValueKey(widget.state.count),
                              count: widget.state.count,
                              color: primary,
                            )
                          : const SizedBox.shrink(key: ValueKey('no-badge')),
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

  /// The glass shape: a 280-wide bar or a 62 dp circle, morphing between.
  Widget _glass(bool collapsed, Color primary) {
    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: AnimatedContainer(
            duration: _morph,
            curve: Curves.easeOutCubic,
            height: collapsed ? 62 : 70,
            width: collapsed ? 62 : 280,
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              layoutBuilder: _fadeOutIgnored,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
              // Fixed-size contents, so nothing squashes while the shape
              // grows or shrinks; the rounded clip hides what's outside.
              child: collapsed
                  ? OverflowBox(
                      key: const ValueKey('bubble'),
                      minWidth: 58,
                      maxWidth: 58,
                      minHeight: 58,
                      maxHeight: 58,
                      child: Center(child: _ring(primary, size: 32)),
                    )
                  : OverflowBox(
                      key: const ValueKey('bar'),
                      alignment: Alignment.centerLeft,
                      minWidth: 277,
                      maxWidth: 277,
                      minHeight: 67,
                      maxHeight: 67,
                      child: _barContents(primary),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _barContents(Color primary) {
    final request = widget.state.latest!;
    final count = widget.state.count;
    return Padding(
      padding: const EdgeInsets.only(left: 22, right: 8),
      child: Row(
        children: [
          Icon(Icons.delete_outline_rounded,
              color: Colors.white.withValues(alpha: 0.8), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    request.message,
                    key: ValueKey(request.id),
                    maxLines: count > 1 ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (count > 1)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: UndoController.undoAll,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3, bottom: 2),
                      child: Text(
                        'Undo all $count',
                        style: TextStyle(
                          color: primary.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(25),
            onTap: UndoController.undo,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ring(primary, size: 26),
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
    );
  }

  /// Countdown ring around the undo arrow.
  Widget _ring(Color primary, {required double size}) => SizedBox(
        width: size,
        height: size,
        child: AnimatedBuilder(
          animation: _countdown,
          builder: (context, _) => Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: 1 - _countdown.value,
                  strokeWidth: 2.5,
                  color: primary,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              Icon(Icons.undo_rounded, size: size * 0.58, color: primary),
            ],
          ),
        ),
      );
}

/// The little count on the bubble; pops each time it changes.
class _Badge extends StatelessWidget {
  final int count;
  final Color color;
  const _Badge({super.key, required this.count, required this.color});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.35, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: Container(
          constraints: const BoxConstraints(minWidth: 22),
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.black, width: 1.5),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
}

/// Keeps the undo dock above a screen's own bottom bar while that screen is
/// on top. Put it around the bar.
class UndoLift extends StatefulWidget {
  final double height;
  final Widget child;
  const UndoLift({super.key, required this.height, required this.child});

  @override
  State<UndoLift> createState() => _UndoLiftState();
}

class _UndoLiftState extends State<UndoLift> {
  static final Map<_UndoLiftState, double> _active = {};

  static void _apply() {
    var v = 0.0;
    for (final h in _active.values) {
      if (h > v) v = h;
    }
    UndoController.lift.value = v;
  }

  // Changed after the frame: the dock can't rebuild while this one builds.
  void _later(VoidCallback f) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        f();
        _apply();
      });

  @override
  Widget build(BuildContext context) {
    // Only while this screen is the top one (not under a pushed page).
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    final h = onTop ? widget.height : 0.0;
    if (_active[this] != h) _later(() => _active[this] = h);
    return widget.child;
  }

  @override
  void dispose() {
    _later(() => _active.remove(this));
    super.dispose();
  }
}
