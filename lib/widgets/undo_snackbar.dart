import 'dart:async';
import 'package:flutter/foundation.dart';

/// One pending "undo" offer.
class UndoRequest {
  final int id;
  final String message;
  final VoidCallback onUndo;
  const UndoRequest(this.id, this.message, this.onUndo);
}

/// App-wide undo offer shown by [UndoHost] (lib/widgets/undo_bar.dart) as a
/// glass pill in the nav bar's spot. Disappears after exactly [duration].
class UndoController {
  UndoController._();

  static const duration = Duration(seconds: 5);
  static final ValueNotifier<UndoRequest?> current = ValueNotifier(null);
  static Timer? _timer;
  static int _seq = 0;

  static void show(String message, VoidCallback onUndo) {
    _timer?.cancel();
    final request = UndoRequest(++_seq, message, onUndo);
    current.value = request;
    _timer = Timer(duration, () {
      if (current.value?.id == request.id) current.value = null;
    });
  }

  static void undo() {
    final request = current.value;
    _timer?.cancel();
    current.value = null;
    request?.onUndo();
  }

  static void dismiss() {
    _timer?.cancel();
    current.value = null;
  }
}

/// Shows "message · UNDO" for 5 seconds.
void showUndo(String message, VoidCallback onUndo) =>
    UndoController.show(message, onUndo);
