import 'package:flutter/material.dart';

/// Floating "Deleted · UNDO" snackbar.
/// [bottomMargin] keeps it above the home screen's floating glass nav bar;
/// pass a small value on screens without that bar.
SnackBar undoSnackBar(
  String message,
  VoidCallback onUndo, {
  double bottomMargin = 110,
}) {
  return SnackBar(
    content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
    duration: const Duration(seconds: 5),
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.fromLTRB(16, 0, 16, bottomMargin),
    action: SnackBarAction(label: 'UNDO', onPressed: onUndo),
  );
}
