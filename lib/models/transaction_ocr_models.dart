// ============================================================================
// SCREENSHOT SCANNING (ML Kit OCR) IS DISABLED
// Vyaya ships fully offline with no internet permission. Google ML Kit adds
// the INTERNET permission and Google usage reporting, so everything used only
// by screenshot scanning is commented out rather than deleted.
// To turn it back on, follow "Re-enabling screenshot scanning" in README.md
// (in each file: select everything below this header and press Ctrl+/).
// ============================================================================
// import 'package:flutter/material.dart';
//
// /// Enum for supported payment apps
// enum PaymentApp {
//   phonePe,
//   googlePay,
//   paytm,
//   unknown;
//
//   String get displayName {
//     switch (this) {
//       case PaymentApp.phonePe:
//         return 'PhonePe';
//       case PaymentApp.googlePay:
//         return 'Google Pay';
//       case PaymentApp.paytm:
//         return 'Paytm';
//       case PaymentApp.unknown:
//         return 'Unknown';
//     }
//   }
//
//   IconData get icon {
//     switch (this) {
//       case PaymentApp.phonePe:
//         return Icons.phone_android;
//       case PaymentApp.googlePay:
//         return Icons.payment;
//       case PaymentApp.paytm:
//         return Icons.account_balance_wallet;
//       case PaymentApp.unknown:
//         return Icons.help_outline;
//     }
//   }
//
//   Color get color {
//     switch (this) {
//       case PaymentApp.phonePe:
//         return const Color(0xFF5F259F);
//       case PaymentApp.googlePay:
//         return const Color(0xFF4285F4);
//       case PaymentApp.paytm:
//         return const Color(0xFF00BAF2);
//       case PaymentApp.unknown:
//         return Colors.grey;
//     }
//   }
// }
//
// /// Model for extracted transaction data
// class ExtractedTransaction {
//   final String? amount;
//   final String? payeeName;
//   final String? date;
//   final String? transactionId;
//   final double confidence;
//
//   ExtractedTransaction({
//     this.amount,
//     this.payeeName,
//     this.date,
//     this.transactionId,
//     required this.confidence,
//   });
//
//   @override
//   String toString() {
//     return 'ExtractedTransaction(amount: $amount, payee: $payeeName, date: $date, confidence: ${confidence.toStringAsFixed(1)}%)';
//   }
// }
//
// /// Model for OCR text block with bounding box
// class TextBlock {
//   final String text;
//   final BoundingBox boundingBox;
//   final double confidence;
//   final List<String> lines;
//   final List<String> recognizedLanguages;
//   final List<Point> cornerPoints;
//
//   TextBlock({
//     required this.text,
//     required this.boundingBox,
//     required this.confidence,
//     required this.lines,
//     required this.recognizedLanguages,
//     required this.cornerPoints,
//   });
// }
//
// /// Model for bounding box coordinates
// class BoundingBox {
//   final int x;
//   final int y;
//   final int width;
//   final int height;
//
//   BoundingBox({
//     required this.x,
//     required this.y,
//     required this.width,
//     required this.height,
//   });
// }
//
// /// Model for point coordinates
// class Point {
//   final double x;
//   final double y;
//
//   Point({required this.x, required this.y});
// }
//
// /// Model for OCR result
// class OcrResult {
//   final List<TextBlock> textBlocks;
//   final String rawText;
//   final DateTime processingTime;
//
//   OcrResult({
//     required this.textBlocks,
//     required this.rawText,
//     required this.processingTime,
//   });
// }
//
// /// Model for crop region coordinates (percentage-based)
// class CropRegion {
//   final double x;
//   final double y;
//   final double width;
//   final double height;
//
//   CropRegion({
//     required this.x,
//     required this.y,
//     required this.width,
//     required this.height,
//   });
// }
//
// /// Template for payment app-specific processing
// class PaymentAppTemplate {
//   final PaymentApp app;
//   final CropRegion cropRegion;
//   final Map<String, CropRegion> fieldRegions;
//   final Map<String, List<String>> fieldKeywords;
//
//   PaymentAppTemplate({
//     required this.app,
//     required this.cropRegion,
//     required this.fieldRegions,
//     required this.fieldKeywords,
//   });
//
//   static PaymentAppTemplate getTemplate(PaymentApp app) {
//     switch (app) {
//       case PaymentApp.phonePe:
//         return PaymentAppTemplate(
//           app: app,
//           // Optimized crop region: top 12%, bottom 24%, left 0%, right 100%
//           cropRegion: CropRegion(x: 0.0, y: 0.12, width: 1.0, height: 0.12),
//           fieldRegions: {
//             // Amount is located in the right 40% of the cropped area (60%-100% left)
//             'amount': CropRegion(x: 0.6, y: 0.0, width: 0.4, height: 1.0),
//             'payee': CropRegion(x: 0.0, y: 0.0, width: 0.6, height: 1.0),
//             'date': CropRegion(x: 0.0, y: 0.0, width: 1.0, height: 0.3),
//           },
//           fieldKeywords: {
//             'amount': ['₹', 'Rs', 'Amount', 'Paid'],
//             'payee': ['To', 'Paid to', 'Receiver', 'Name'],
//             'date': ['Date', 'Time', 'On'],
//           },
//         );
//       case PaymentApp.googlePay:
//         return PaymentAppTemplate(
//           app: app,
//           cropRegion: CropRegion(x: 0.0, y: 0.1, width: 1.0, height: 0.8),
//           fieldRegions: {
//             'amount': CropRegion(x: 0.1, y: 0.15, width: 0.8, height: 0.25),
//             'payee': CropRegion(x: 0.1, y: 0.45, width: 0.8, height: 0.2),
//             'date': CropRegion(x: 0.1, y: 0.75, width: 0.8, height: 0.1),
//           },
//           fieldKeywords: {
//             'amount': ['₹', 'Rs', 'Amount', 'Sent', 'Paid'],
//             'payee': ['To', 'Sent to', 'Recipient', 'Name'],
//             'date': ['Date', 'Time', 'Today', 'Yesterday'],
//           },
//         );
//       case PaymentApp.paytm:
//         return PaymentAppTemplate(
//           app: app,
//           cropRegion: CropRegion(x: 0.0, y: 0.1, width: 1.0, height: 0.8),
//           fieldRegions: {
//             'amount': CropRegion(x: 0.1, y: 0.2, width: 0.8, height: 0.3),
//             'payee': CropRegion(x: 0.1, y: 0.4, width: 0.8, height: 0.2),
//             'date': CropRegion(x: 0.1, y: 0.7, width: 0.8, height: 0.1),
//           },
//           fieldKeywords: {
//             'amount': ['₹', 'Rs', 'Amount', 'Paid'],
//             'payee': ['To', 'Paid to', 'Merchant', 'Name'],
//             'date': ['Date', 'Time', 'On'],
//           },
//         );
//       case PaymentApp.unknown:
//         return PaymentAppTemplate(
//           app: app,
//           cropRegion: CropRegion(x: 0.0, y: 0.0, width: 1.0, height: 1.0),
//           fieldRegions: {},
//           fieldKeywords: {},
//         );
//     }
//   }
// }
//
// /// Models for OCR (Optical Character Recognition) transaction processing
//
// class TransactionOCRResult {
//   final String rawText;
//   final double? amount;
//   final String? payee;
//   final String? paymentApp;
//   final String? transactionId;
//   final DateTime? transactionDate;
//   final double confidence;
//   final List<String> extractedFields;
//
//   TransactionOCRResult({
//     required this.rawText,
//     this.amount,
//     this.payee,
//     this.paymentApp,
//     this.transactionId,
//     this.transactionDate,
//     this.confidence = 0.0,
//     this.extractedFields = const [],
//   });
//
//   Map<String, dynamic> toMap() {
//     return {
//       'rawText': rawText,
//       'amount': amount,
//       'payee': payee,
//       'paymentApp': paymentApp,
//       'transactionId': transactionId,
//       'transactionDate': transactionDate?.toIso8601String(),
//       'confidence': confidence,
//       'extractedFields': extractedFields,
//     };
//   }
//
//   factory TransactionOCRResult.fromMap(Map<String, dynamic> map) {
//     return TransactionOCRResult(
//       rawText: map['rawText'] ?? '',
//       amount: map['amount']?.toDouble(),
//       payee: map['payee'],
//       paymentApp: map['paymentApp'],
//       transactionId: map['transactionId'],
//       transactionDate: map['transactionDate'] != null
//           ? DateTime.parse(map['transactionDate'])
//           : null,
//       confidence: (map['confidence'] ?? 0.0).toDouble(),
//       extractedFields: List<String>.from(map['extractedFields'] ?? []),
//     );
//   }
//
//   bool get isValid => amount != null && amount! > 0;
// }
//
// class OCRTextBlock {
//   final String text;
//   final double confidence;
//   final int lineNumber;
//   final String fieldType; // amount, payee, date, etc.
//
//   OCRTextBlock({
//     required this.text,
//     required this.confidence,
//     required this.lineNumber,
//     this.fieldType = 'unknown',
//   });
//
//   factory OCRTextBlock.fromMap(Map<String, dynamic> map) {
//     return OCRTextBlock(
//       text: map['text'] ?? '',
//       confidence: (map['confidence'] ?? 0.0).toDouble(),
//       lineNumber: map['lineNumber'] ?? 0,
//       fieldType: map['fieldType'] ?? 'unknown',
//     );
//   }
//
//   Map<String, dynamic> toMap() {
//     return {
//       'text': text,
//       'confidence': confidence,
//       'lineNumber': lineNumber,
//       'fieldType': fieldType,
//     };
//   }
// }
//
// class PaymentAppPatterns {
//   static const Map<String, List<String>> patterns = {
//     'paytm': ['paytm', 'paid via paytm', 'paytm payment'],
//     'phonepe': ['phonepe', 'phone pe', 'paid via phonepe'],
//     'googlepay': ['google pay', 'gpay', 'g pay', 'paid using google pay'],
//     'amazonpay': ['amazon pay', 'amazon payment', 'paid via amazon'],
//     'bhim': ['bhim', 'bhim upi', 'upi payment'],
//     'mobikwik': ['mobikwik', 'mobi kwik', 'paid via mobikwik'],
//     'freecharge': ['freecharge', 'free charge', 'paid via freecharge'],
//     'paypal': ['paypal', 'paid via paypal'],
//     'razorpay': ['razorpay', 'razor pay', 'paid via razorpay'],
//     'cashfree': ['cashfree', 'cash free', 'paid via cashfree'],
//   };
//
//   static String? detectPaymentApp(String text) {
//     final lowerText = text.toLowerCase();
//
//     for (final entry in patterns.entries) {
//       for (final pattern in entry.value) {
//         if (lowerText.contains(pattern)) {
//           return entry.key;
//         }
//       }
//     }
//
//     return null;
//   }
// }
