// ============================================================================
// SCREENSHOT SCANNING (ML Kit OCR) IS DISABLED
// Vyaya ships fully offline with no internet permission. Google ML Kit adds
// the INTERNET permission and Google usage reporting, so everything used only
// by screenshot scanning is commented out rather than deleted.
// To turn it back on, follow "Re-enabling screenshot scanning" in README.md
// (in each file: select everything below this header and press Ctrl+/).
// ============================================================================
// import 'dart:io';
// import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
// import '../models/transaction_ocr_models.dart' as models;
//
// /// Primary OCR service using Google ML Kit
// class PrimaryOcrService {
//   static TextRecognizer? _textRecognizer;
//
//   /// Get or create text recognizer instance
//   static TextRecognizer get textRecognizer {
//     _textRecognizer ??= TextRecognizer();
//     return _textRecognizer!;
//   }
//
//   /// Extract text from image using Google ML Kit
//   static Future<models.OcrResult> extractText(File imageFile) async {
//     InputImage? inputImage;
//
//     try {
//       // Validate file exists and is readable
//       if (!await imageFile.exists()) {
//         throw Exception('Image file does not exist');
//       }
//
//       final fileSize = await imageFile.length();
//       if (fileSize == 0) {
//         throw Exception('Image file is empty');
//       }
//
//       // Create input image with error handling
//       inputImage = InputImage.fromFile(imageFile);
//
//       // Process image with timeout
//       final recognizedText = await textRecognizer.processImage(inputImage).timeout(
//           const Duration(seconds: 30),
//           onTimeout: () {
//             throw Exception('OCR processing timed out');
//           });
//
//       final textBlocks = <models.TextBlock>[];
//
//       // Process recognized text blocks safely
//       for (final block in recognizedText.blocks) {
//         try {
//           for (final line in block.lines) {
//             final boundingBox = line.boundingBox;
//
//             // Validate bounding box
//             if (boundingBox.left.isNaN ||
//                 boundingBox.top.isNaN ||
//                 boundingBox.right.isNaN ||
//                 boundingBox.bottom.isNaN) {
//               continue; // Skip invalid bounding boxes
//             }
//
//             textBlocks.add(
//               models.TextBlock(
//                 text: line.text.trim(),
//                 boundingBox: models.BoundingBox(
//                   x: boundingBox.left.round().clamp(0, 10000),
//                   y: boundingBox.top.round().clamp(0, 10000),
//                   width: (boundingBox.right - boundingBox.left).round().clamp(1, 10000),
//                   height: (boundingBox.bottom - boundingBox.top).round().clamp(1, 10000),
//                 ),
//                 confidence: (line.confidence ?? 0.0).clamp(0.0, 1.0),
//                 lines: [line.text.trim()],
//                 recognizedLanguages: line.recognizedLanguages.map((lang) => lang.toString()).toList(),
//                 cornerPoints: line.cornerPoints.map((point) =>
//                   models.Point(
//                     x: point.x.toDouble().clamp(0.0, 10000.0),
//                     y: point.y.toDouble().clamp(0.0, 10000.0)
//                   )
//                 ).toList(),
//               ),
//             );
//           }
//         } catch (blockError) {
//           continue; // Skip problematic blocks
//         }
//       }
//
//       return models.OcrResult(
//         textBlocks: textBlocks,
//         rawText: recognizedText.text.trim(),
//         processingTime: DateTime.now(),
//       );
//     } catch (e) {
//       // Return empty result instead of crashing
//       return models.OcrResult(
//         textBlocks: [],
//         rawText: '',
//         processingTime: DateTime.now(),
//       );
//     } finally {
//       // Clean up resources
//       inputImage = null;
//     }
//   }
//
//   /// Extract text from multiple region crops
//   static Future<Map<String, models.OcrResult>> extractTextFromRegions(
//       List<File> regionCrops) async {
//     final results = <String, models.OcrResult>{};
//
//     for (int i = 0; i < regionCrops.length; i++) {
//       final cropFile = regionCrops[i];
//       final regionName = _getRegionNameFromPath(cropFile.path);
//
//       try {
//         final result = await extractText(cropFile);
//         results[regionName] = result;
//       } catch (e) {
//         // Continue with other regions
//       }
//     }
//
//     return results;
//   }
//
//   static String _getRegionNameFromPath(String path) {
//     final fileName = path.split('/').last;
//     if (fileName.contains('amount')) return 'amount';
//     if (fileName.contains('payee')) return 'payee';
//     if (fileName.contains('date')) return 'date';
//     return 'unknown';
//   }
//
//   /// Clean up resources
//   static Future<void> dispose() async {
//     try {
//       await _textRecognizer?.close();
//       _textRecognizer = null;
//     } catch (e) {
//       // Error disposing OCR resources - ignore
//     }
//   }
// }
