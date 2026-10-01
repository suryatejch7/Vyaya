import 'dart:async';
import 'package:flutter/foundation.dart';

/// One pending "undo" offer.
class UndoRequest {
  final int id;
  final String message;
  final FutureOr<void> Function() onUndo;
  const UndoRequest(this.id, this.message, this.onUndo);
}

/// What the undo dock shows right now.
@immutable
class UndoState {
  /// Offers still open, oldest first. Empty = nothing shown.
  final List<UndoRequest> items;

  /// Small round bubble instead of the full bar.
  final bool collapsed;

  /// Goes up each time the 5-second countdown starts over, so the ring
  /// restarts with it.
  final int round;

  const UndoState(this.items, this.collapsed, this.round);
  static const empty = UndoState([], false, 0);

  UndoRequest? get latest => items.isEmpty ? null : items.last;
  int get count => items.length;
}

/// App-wide undo, shown by [UndoHost] (lib/widgets/undo_bar.dart).
///
/// - The first action shows the full bar ("Dismissed Swiggy · UNDO").
/// - Another action while it's still up shrinks it into a small bubble with
///   a countdown ring and a count, so a run of dismissals doesn't keep a bar
///   on screen. Tap the bubble to open it again.
/// - Nothing is lost: every action stays undoable (latest first, or all at
///   once) until 5 seconds after the last one.
class UndoController {
  UndoController._();

  static const duration = Duration(seconds: 5);
  static final ValueNotifier<UndoState> state = ValueNotifier(UndoState.empty);

  /// The full bar's message while it covers the nav bar's spot, else null.
  /// (The nav bar fades out only while this is set.)
  static final ValueNotifier<UndoRequest?> current = ValueNotifier(null);

  /// Extra space to keep below the dock, e.g. for a screen's bottom bar.
  static final ValueNotifier<double> lift = ValueNotifier(0);

  static Timer? _timer;
  static int _seq = 0;

  /// Every change also starts the 5 seconds over.
  static void _set(List<UndoRequest> items, bool collapsed) {
    final old = state.value;
    _timer?.cancel();
    _timer = items.isEmpty ? null : Timer(duration, dismiss);
    state.value = UndoState(List.unmodifiable(items),
        items.isNotEmpty && collapsed, old.round + 1);
    current.value = (items.isEmpty || collapsed) ? null : items.last;
  }

  static void show(String message, FutureOr<void> Function() onUndo) {
    final s = state.value;
    final items = [...s.items, UndoRequest(++_seq, message, onUndo)];
    // Second action in a row: tuck the bar away into the bubble.
    _set(items, items.length > 1);
  }

  /// Bubble tapped: open the bar, with a fresh 5 seconds to decide.
  static void expand() {
    final s = state.value;
    if (s.items.isEmpty || !s.collapsed) return;
    _set(s.items, false);
  }

  /// Undoes the latest action. Others stay open (with a fresh countdown).
  static Future<void> undo() async {
    final s = state.value;
    if (s.items.isEmpty) return;
    final request = s.items.last;
    _set(s.items.sublist(0, s.items.length - 1), s.collapsed);
    await _run(request);
  }

  /// Undoes every open action, newest first.
  static Future<void> undoAll() async {
    final items = state.value.items.reversed.toList();
    _set(const [], false);
    for (final r in items) {
      await _run(r);
    }
  }

  /// Closes it; the actions stay done.
  static void dismiss() => _set(const [], false);

  static Future<void> _run(UndoRequest r) async {
    try {
      await r.onUndo();
    } catch (e) {
      debugPrint('Undo failed: $e');
    }
  }
}

/// Shows "message · UNDO" for 5 seconds.
void showUndo(String message, FutureOr<void> Function() onUndo) =>
    UndoController.show(message, onUndo);
