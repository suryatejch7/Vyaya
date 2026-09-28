// ============================================================================
// SCREENSHOT SCANNING (ML Kit OCR) IS DISABLED
// Vyaya ships fully offline with no internet permission. Google ML Kit adds
// the INTERNET permission and Google usage reporting, so everything used only
// by screenshot scanning is commented out rather than deleted.
// To turn it back on, follow "Re-enabling screenshot scanning" in README.md
// (in each file: select everything below this header and press Ctrl+/).
// ============================================================================
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:receive_sharing_intent/receive_sharing_intent.dart';
// import '../screens/transaction_scanner_screen.dart';
//
// class SharingIntentService {
//   static BuildContext? _context;
//   static bool _isInitialized = false;
//
//   static Future<void> initialize() async {
//     // This method is required by main.dart but doesn't need to do anything
//     // The actual initialization happens in setContext
//   }
//
//   static void setContext(BuildContext context) {
//     _context = context;
//     if (!_isInitialized) {
//       _initialize();
//       _isInitialized = true;
//     }
//   }
//
//   static void _initialize() {
//     // Handle sharing intent when app is already running
//     ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> files) {
//       if (files.isNotEmpty && _context != null) {
//         _handleSharedFiles(files);
//       }
//     });
//
//     // Handle sharing intent when app is launched from sharing
//     ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> files) {
//       if (files.isNotEmpty && _context != null) {
//         _handleSharedFiles(files);
//       }
//     });
//   }
//
//   static void _handleSharedFiles(List<SharedMediaFile> files) {
//     if (_context == null) return;
//
//     for (SharedMediaFile file in files) {
//       if (file.type == SharedMediaType.image) {
//         // Navigate to scanner screen with the shared image
//         Navigator.of(_context!).push(
//           MaterialPageRoute(
//             builder: (context) => TransactionScannerScreen(
//               initialImage: File(file.path),
//             ),
//           ),
//         );
//         break; // Only handle the first image
//       }
//     }
//   }
//
//   static void dispose() {
//     _context = null;
//     _isInitialized = false;
//   }
// }
