// ============================================================================
// SCREENSHOT SCANNING (ML Kit OCR) IS DISABLED
// Vyaya ships fully offline with no internet permission. Google ML Kit adds
// the INTERNET permission and Google usage reporting, so everything used only
// by screenshot scanning is commented out rather than deleted.
// To turn it back on, follow "Re-enabling screenshot scanning" in README.md
// (in each file: select everything below this header and press Ctrl+/).
// ============================================================================
// import 'dart:io';
// import 'package:image/image.dart' as img;
// import '../models/transaction_ocr_models.dart';
//
// /// Service for preprocessing transaction screenshots
// class ImagePreprocessingService {
//   /// Preprocess image based on selected payment app
//   static Future<File> preprocessImage(File imageFile, PaymentApp app) async {
//     try {
//       // Read image
//       final bytes = await imageFile.readAsBytes();
//       img.Image? originalImage = img.decodeImage(bytes);
//
//       if (originalImage == null) {
//         throw Exception('Failed to decode image');
//       }
//
//       // Step 1: Crop based on app template
//       img.Image croppedImage = _cropForApp(originalImage, app);
//
//       // Step 2: Convert to grayscale
//       croppedImage = img.grayscale(croppedImage);
//
//       // Step 3: Apply Gaussian blur then sharpen
//       croppedImage = img.gaussianBlur(croppedImage, radius: 1);
//       croppedImage = _sharpenImage(croppedImage);
//
//       // Step 4: Enhance contrast
//       croppedImage = _enhanceContrast(croppedImage);
//
//       // Step 5: Apply binary thresholding for better OCR
//       final processedImage = _applyAdaptiveThreshold(croppedImage);
//
//       // Save processed image
//       final processedPath =
//           '${imageFile.parent.path}/processed_${DateTime.now().millisecondsSinceEpoch}.png';
//       final processedFile = File(processedPath);
//       await processedFile.writeAsBytes(img.encodePng(processedImage));
//
//       return processedFile;
//     } catch (e) {
//       throw Exception('Image preprocessing failed: $e');
//     }
//   }
//
//   /// Crop image based on app-specific templates
//   static img.Image _cropForApp(img.Image image, PaymentApp app) {
//     final template = PaymentAppTemplate.getTemplate(app);
//
//     // Default: use template crop region
//     final cropX = (image.width * template.cropRegion.x).round();
//     final cropY = (image.height * template.cropRegion.y).round();
//     final cropWidth = (image.width * template.cropRegion.width).round();
//     final cropHeight = (image.height * template.cropRegion.height).round();
//
//     final safeX = cropX.clamp(0, image.width - 1);
//     final safeY = cropY.clamp(0, image.height - 1);
//     final safeWidth = cropWidth.clamp(1, image.width - safeX);
//     final safeHeight = cropHeight.clamp(1, image.height - safeY);
//
//     return img.copyCrop(
//       image,
//       x: safeX,
//       y: safeY,
//       width: safeWidth,
//       height: safeHeight,
//     );
//   }
//
//   /// Apply adaptive thresholding
//   static img.Image _applyAdaptiveThreshold(img.Image image) {
//     // Calculate global mean luminance
//     int sum = 0;
//     int count = 0;
//     for (int y = 0; y < image.height; y++) {
//       for (int x = 0; x < image.width; x++) {
//         final pixel = image.getPixel(x, y);
//         sum += img.getLuminance(pixel).toInt();
//         count++;
//       }
//     }
//     final mean = (sum / count).round();
//
//     // Apply threshold based on mean
//     for (int y = 0; y < image.height; y++) {
//       for (int x = 0; x < image.width; x++) {
//         final pixel = image.getPixel(x, y);
//         final luminance = img.getLuminance(pixel);
//         final newPixel = luminance > mean
//             ? img.ColorRgb8(255, 255, 255)
//             : img.ColorRgb8(0, 0, 0);
//         image.setPixel(x, y, newPixel);
//       }
//     }
//     return image;
//   }
//
//   /// Apply basic binary thresholding
//   static img.Image _applyThreshold(img.Image image) {
//     const threshold = 128;
//
//     for (int y = 0; y < image.height; y++) {
//       for (int x = 0; x < image.width; x++) {
//         final pixel = image.getPixel(x, y);
//         final luminance = img.getLuminance(pixel);
//
//         final newPixel = luminance > threshold
//             ? img.ColorRgb8(255, 255, 255) // White
//             : img.ColorRgb8(0, 0, 0); // Black
//
//         image.setPixel(x, y, newPixel);
//       }
//     }
//
//     return image;
//   }
//
//   /// Apply improved sharpening filter
//   static img.Image _sharpenImage(img.Image image) {
//     // Stronger sharpening kernel
//     final kernel = [0, -2, 0, -2, 11, -2, 0, -2, 0];
//     return img.convolution(image, filter: kernel);
//   }
//
//   /// Enhance contrast
//   static img.Image _enhanceContrast(img.Image image) {
//     const factor = 1.5;
//
//     for (int y = 0; y < image.height; y++) {
//       for (int x = 0; x < image.width; x++) {
//         final pixel = image.getPixel(x, y);
//         final r = pixel.r.round();
//         final g = pixel.g.round();
//         final b = pixel.b.round();
//
//         final newR = ((r - 128) * factor + 128).clamp(0, 255).round();
//         final newG = ((g - 128) * factor + 128).clamp(0, 255).round();
//         final newB = ((b - 128) * factor + 128).clamp(0, 255).round();
//
//         image.setPixel(x, y, img.ColorRgb8(newR, newG, newB));
//       }
//     }
//
//     return image;
//   }
//
//   /// Preprocess PhonePe image into two separate crops: left 60% (payee) and right 40% (amount)
//   static Future<Map<String, File>> preprocessPhonePeDualCrops(
//     File imageFile, {
//     double cropTop = 0.17,
//     double cropBottom = 0.21,
//   }) async {
//     try {
//       // Read image
//       final bytes = await imageFile.readAsBytes();
//       img.Image? originalImage = img.decodeImage(bytes);
//
//       if (originalImage == null) {
//         throw Exception('Failed to decode image');
//       }
//
//       // Step 1: Crop to the horizontal strip using user-defined crop settings
//       final stripY = (originalImage.height * cropTop).round();
//       final stripHeight = (originalImage.height * (cropBottom - cropTop))
//           .round();
//       final stripImage = img.copyCrop(
//         originalImage,
//         x: 0,
//         y: stripY,
//         width: originalImage.width,
//         height: stripHeight,
//       );
//
//       // Step 2: Create left 60% crop (payee region)
//       final payeeWidth = (stripImage.width * 0.6).round();
//       final payeeCrop = img.copyCrop(
//         stripImage,
//         x: 0,
//         y: 0,
//         width: payeeWidth,
//         height: stripImage.height,
//       );
//
//       // Step 3: Create right 40% crop (amount region)
//       final amountX = (stripImage.width * 0.6).round();
//       final amountWidth = stripImage.width - amountX;
//       final amountCrop = img.copyCrop(
//         stripImage,
//         x: amountX,
//         y: 0,
//         width: amountWidth,
//         height: stripImage.height,
//       );
//
//       // Step 4: Apply preprocessing to both crops
//       final processedPayee = _preprocessForPayee(payeeCrop);
//       final processedAmount = _preprocessForAmount(amountCrop);
//
//       // Step 5: Save both processed crops
//       final payeePath =
//           '${imageFile.parent.path}/payee_crop_${DateTime.now().millisecondsSinceEpoch}.png';
//       final amountPath =
//           '${imageFile.parent.path}/amount_crop_${DateTime.now().millisecondsSinceEpoch}.png';
//
//       final payeeFile = File(payeePath);
//       final amountFile = File(amountPath);
//
//       await payeeFile.writeAsBytes(img.encodePng(processedPayee));
//       await amountFile.writeAsBytes(img.encodePng(processedAmount));
//
//       return {'payee': payeeFile, 'amount': amountFile};
//     } catch (e) {
//       throw Exception('Dual crop preprocessing failed: $e');
//     }
//   }
//
//   /// Preprocessing optimized for payee name recognition (gentle processing)
//   static img.Image _preprocessForPayee(img.Image crop) {
//     // Light preprocessing to preserve text readability
//     img.Image processed = img.grayscale(crop);
//     processed = img.gaussianBlur(processed, radius: 1);
//     processed = _sharpenImage(processed);
//     processed = _applyThreshold(processed);
//     return processed;
//   }
//
//   /// Preprocessing optimized for amount recognition (enhanced processing)
//   static img.Image _preprocessForAmount(img.Image crop) {
//     // Enhanced preprocessing for better number recognition
//     img.Image processed = img.grayscale(crop);
//     processed = img.gaussianBlur(processed, radius: 1);
//     processed = _sharpenImage(processed);
//     processed = _enhanceContrast(processed);
//     processed = _applyAdaptiveThreshold(processed);
//     return processed;
//   }
//
//   /// Clean up temporary processed image files
//   static Future<void> cleanupTempFiles(List<File> files) async {
//     for (final file in files) {
//       try {
//         if (await file.exists()) {
//           await file.delete();
//         }
//       } catch (_) {
//         // Best effort cleanup — ignore failures
//       }
//     }
//   }
// }
