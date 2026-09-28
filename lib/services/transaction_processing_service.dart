// ============================================================================
// SCREENSHOT SCANNING (ML Kit OCR) IS DISABLED
// Vyaya ships fully offline with no internet permission. Google ML Kit adds
// the INTERNET permission and Google usage reporting, so everything used only
// by screenshot scanning is commented out rather than deleted.
// To turn it back on, follow "Re-enabling screenshot scanning" in README.md
// (in each file: select everything below this header and press Ctrl+/).
// ============================================================================
// import 'dart:io';
// import '../models/transaction_ocr_models.dart';
// import '../models/user_settings.dart';
// import 'image_preprocessing_service.dart';
// import 'primary_ocr_service.dart';
// import 'field_extraction_service.dart';
// import 'text_normalization_service.dart';
//
// /// Main service orchestrating the complete transaction processing pipeline
// class TransactionProcessingService {
//   /// Process transaction screenshot with user's crop settings
//   static Future<ProcessingResult> processTransactionScreenshotWithUserSettings(
//     File imageFile,
//     UserSettings userSettings, {
//     Function(double)? onProgress,
//   }) async {
//     return processTransactionScreenshot(
//       imageFile,
//       onProgress: onProgress,
//       cropTop: userSettings.cropTop,
//       cropBottom: userSettings.cropBottom,
//     );
//   }
//
//   /// Process transaction screenshot with complete pipeline (PhonePe only)
//   static Future<ProcessingResult> processTransactionScreenshot(
//     File imageFile, {
//     Function(double)? onProgress,
//     double cropTop = 0.17,
//     double cropBottom = 0.21,
//   }) async {
//     List<String> processingSteps = [];
//     // Hardcoded to PhonePe since you only use PhonePe
//     Map<String, File>? dualCrops;
//
//     try {
//       onProgress?.call(0.1);
//       processingSteps.add('Starting PhonePe transaction processing...');
//
//       // Validate input file
//       if (!await imageFile.exists()) {
//         throw Exception('Image file does not exist');
//       }
//
//       final fileSize = await imageFile.length();
//       if (fileSize == 0) {
//         throw Exception('Image file is empty');
//       }
//
//       if (fileSize > 50 * 1024 * 1024) {
//         // 50MB limit
//         throw Exception('Image file too large (>50MB)');
//       }
//
//       // Step 1: Image Preprocessing - Use dual-crop approach for PhonePe
//       onProgress?.call(0.2);
//       processingSteps.add(
//         'Preprocessing image with PhonePe dual-crop settings...',
//       );
//
//       try {
//         // Create separate crops for payee (left 60%) and amount (right 40%) using user crop settings
//         dualCrops = await ImagePreprocessingService.preprocessPhonePeDualCrops(
//           imageFile,
//           cropTop: cropTop,
//           cropBottom: cropBottom,
//         ).timeout(const Duration(seconds: 30));
//       } catch (e) {
//         dualCrops = null;
//       }
//
//       // Step 2: Dual OCR with Google ML Kit on both crops
//       onProgress?.call(0.3);
//       processingSteps.add('Extracting text using dual-crop OCR...');
//
//       ExtractedTransaction extractedData;
//
//       if (dualCrops != null) {
//         // Process both crops separately for optimal extraction
//         final payeeOcr = await PrimaryOcrService.extractText(
//           dualCrops['payee']!,
//         ).timeout(const Duration(minutes: 1));
//         final amountOcr = await PrimaryOcrService.extractText(
//           dualCrops['amount']!,
//         ).timeout(const Duration(minutes: 1));
//
//         // Extract using the WORKING GitHub logic for payee and CURRENT logic for amount with user crop settings
//         final payeeExtracted = FieldExtractionService.extractPayeeFromLeftCrop(
//           payeeOcr.textBlocks,
//         );
//         final amountExtracted =
//             FieldExtractionService.extractAmountFromRightCrop(
//               amountOcr.textBlocks,
//             );
//
//         // Combine results
//         extractedData = ExtractedTransaction(
//           amount: amountExtracted,
//           payeeName: payeeExtracted,
//           date: null,
//           transactionId: null,
//           confidence: _calculateCombinedConfidence([
//             amountExtracted,
//             payeeExtracted,
//           ]),
//         );
//
//         processingSteps.add(
//           'Dual-crop extraction completed: ${payeeExtracted != null ? "Payee found" : "Payee not found"}, ${amountExtracted != null ? "Amount found" : "Amount not found"}',
//         );
//       } else {
//         // Fallback to single image processing if dual-crop fails
//         // Use the same dual-crop approach but with fallback extraction
//         final fallbackCrops =
//             await ImagePreprocessingService.preprocessPhonePeDualCrops(
//               imageFile,
//               cropTop: cropTop,
//               cropBottom: cropBottom,
//             ).timeout(const Duration(seconds: 30));
//
//         final payeeOcr = await PrimaryOcrService.extractText(
//           fallbackCrops['payee']!,
//         ).timeout(const Duration(minutes: 1));
//         final amountOcr = await PrimaryOcrService.extractText(
//           fallbackCrops['amount']!,
//         ).timeout(const Duration(minutes: 1));
//
//         // Extract using the same methods as dual-crop
//         final payeeExtracted = FieldExtractionService.extractPayeeFromLeftCrop(
//           payeeOcr.textBlocks,
//         );
//         final amountExtracted =
//             FieldExtractionService.extractAmountFromRightCrop(
//               amountOcr.textBlocks,
//             );
//
//         extractedData = ExtractedTransaction(
//           amount: amountExtracted,
//           payeeName: payeeExtracted,
//           date: null,
//           transactionId: null,
//           confidence: _calculateCombinedConfidence([
//             amountExtracted,
//             payeeExtracted,
//           ]),
//         );
//         processingSteps.add('Fallback extraction completed');
//       }
//
//       // Step 4: Text Normalization (simplified for PhonePe)
//       onProgress?.call(0.6);
//       processingSteps.add('Processing extracted data...');
//
//       // Skip complex normalization and use extracted data directly
//       final normalizedData = extractedData;
//
//       // Step 5: Secondary OCR (DISABLED - Using Google ML Kit only)
//       onProgress?.call(0.8);
//       processingSteps.add('Finalizing transaction data...');
//
//       // Skip secondary OCR entirely to prevent crashes
//       // Google ML Kit provides sufficient accuracy for PhonePe transactions
//       final enhancedData = normalizedData;
//
//       onProgress?.call(1.0);
//       processingSteps.add(
//         'PhonePe transaction processing completed successfully!',
//       );
//
//       return ProcessingResult(
//         success: true,
//         extractedTransaction: enhancedData,
//         processingSteps: processingSteps,
//         confidence: enhancedData.confidence,
//       );
//     } catch (e) {
//       processingSteps.add('Error: ${e.toString()}');
//
//       return ProcessingResult(
//         success: false,
//         error: e.toString(),
//         processingSteps: processingSteps,
//         confidence: 0.0,
//       );
//     } finally {
//       // Clean up temp processed image files
//       if (dualCrops != null) {
//         await ImagePreprocessingService.cleanupTempFiles(
//           dualCrops.values.toList(),
//         );
//       }
//       // Clean up OCR resources
//       try {
//         await PrimaryOcrService.dispose();
//       } catch (e) {
//         // Cleanup warning ignored
//       }
//     }
//   }
//
//   /// Validate extracted transaction data
//   static ValidationResult validateExtractedData(
//     ExtractedTransaction transaction,
//   ) {
//     final issues = <String>[];
//
//     if (transaction.amount == null || transaction.amount!.isEmpty) {
//       issues.add('Amount not detected');
//     } else {
//       // Validate amount format
//       final amountValue = double.tryParse(transaction.amount!);
//       if (amountValue == null || amountValue <= 0) {
//         issues.add('Invalid amount format');
//       }
//     }
//
//     if (transaction.payeeName == null || transaction.payeeName!.isEmpty) {
//       issues.add('Payee name not detected');
//     } else if (transaction.payeeName!.length < 2) {
//       issues.add('Payee name too short');
//     }
//
//     if (transaction.date == null || transaction.date!.isEmpty) {
//       issues.add('Date not detected');
//     } else {
//       // Try to parse the date
//       try {
//         TextNormalizationService.normalizeDate(transaction.date!);
//       } catch (e) {
//         issues.add('Invalid date format');
//       }
//     }
//
//     return ValidationResult(
//       isValid: issues.isEmpty,
//       issues: issues,
//       confidence: transaction.confidence,
//     );
//   }
//
//   /// Clean amount to fix OCR "7" prefix issue
//
//   /// Calculate combined confidence from multiple fields
//   static double _calculateCombinedConfidence(List<String?> fields) {
//     final nonNullFields = fields.where((f) => f != null && f.isNotEmpty).length;
//     return (nonNullFields / fields.length) * 100;
//   }
// }
//
// /// Result of the complete processing pipeline
// class ProcessingResult {
//   final bool success;
//   final ExtractedTransaction? extractedTransaction;
//   final String? error;
//   final List<String> processingSteps;
//   final double confidence;
//
//   ProcessingResult({
//     required this.success,
//     this.extractedTransaction,
//     this.error,
//     required this.processingSteps,
//     this.confidence = 0.0,
//   });
// }
//
// /// Result of transaction data validation
// class ValidationResult {
//   final bool isValid;
//   final List<String> issues;
//   final double confidence;
//
//   ValidationResult({
//     required this.isValid,
//     required this.issues,
//     required this.confidence,
//   });
// }
