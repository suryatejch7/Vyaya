// ============================================================================
// SCREENSHOT SCANNING (ML Kit OCR) IS DISABLED
// Vyaya ships fully offline with no internet permission. Google ML Kit adds
// the INTERNET permission and Google usage reporting, so everything used only
// by screenshot scanning is commented out rather than deleted.
// To turn it back on, follow "Re-enabling screenshot scanning" in README.md
// (in each file: select everything below this header and press Ctrl+/).
// ============================================================================
// import '../models/transaction_ocr_models.dart';
//
// class FieldExtractionService {
//
//   static ExtractedTransaction extractFields(
//     OcrResult ocrResult,
//     PaymentApp app, {
//     double cropTop = 0.17,
//     double cropBottom = 0.21,
//   }) {
//     final template = PaymentAppTemplate.getTemplate(app);
//
//     final amount = _extractAmount(ocrResult.textBlocks, template, cropTop: cropTop, cropBottom: cropBottom);
//     final payee = _extractPayee(ocrResult.textBlocks, template, cropTop: cropTop, cropBottom: cropBottom);
//
//     return ExtractedTransaction(
//       amount: amount,
//       payeeName: payee,
//       date: null,
//       transactionId: null,
//       confidence: _calculateOverallConfidence([amount, payee]),
//     );
//   }
//
//   static String? _extractAmount(
//     List<TextBlock> textBlocks, 
//     PaymentAppTemplate template, {
//     double cropTop = 0.17,
//     double cropBottom = 0.21,
//   }) {
//     if (template.app == PaymentApp.phonePe) {
//       return _extractPhonePeAmount(textBlocks, template, cropTop: cropTop, cropBottom: cropBottom);
//     }
//
//     for (final block in textBlocks) {
//       final text = block.text.trim();
//
//       // Look for ₹ symbol followed by numbers
//       final rupeePattern = RegExp(r'₹\s*(\d+(?:[,\.]\d+)*)');
//       final rupeeMatch = rupeePattern.firstMatch(text);
//       if (rupeeMatch != null) {
//         final amount = rupeeMatch.group(1)!.replaceAll(',', '');
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue > 0 && numValue < 100000) {
//           return '₹$amount';
//         }
//       }
//
//       // Look for Rs followed by numbers
//       final rsPattern = RegExp(r'Rs\.?\s*(\d+(?:[,\.]\d+)*)');
//       final rsMatch = rsPattern.firstMatch(text);
//       if (rsMatch != null) {
//         final amount = rsMatch.group(1)!.replaceAll(',', '');
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue > 0 && numValue < 100000) {
//           return '₹$amount';
//         }
//       }
//
//       final numberPattern = RegExp(r'\b(\d{1,5}(?:\.\d{1,2})?)\b');
//       final numberMatch = numberPattern.firstMatch(text);
//       if (numberMatch != null) {
//         String amount = numberMatch.group(1)!;
//
//         if (amount.startsWith('7')) {
//           amount = amount.substring(1);
//         }
//
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue > 10 && numValue < 50000) {
//           return '₹$amount';
//         }
//       }
//     }
//
//     return null;
//   }
//
//   static String? _extractPhonePeAmount(
//     List<TextBlock> textBlocks, 
//     PaymentAppTemplate template, {
//     double cropTop = 0.17,
//     double cropBottom = 0.21,
//   }) {
//     final amountRegion = template.fieldRegions['amount'];
//     if (amountRegion == null) return null;
//
//     double maxX = 0, maxY = 0;
//     for (final block in textBlocks) {
//       final rightX = (block.boundingBox.x + block.boundingBox.width).toDouble();
//       final bottomY = (block.boundingBox.y + block.boundingBox.height).toDouble();
//       if (rightX > maxX) maxX = rightX;
//       if (bottomY > maxY) maxY = bottomY;
//     }
//
//     if (maxX == 0 || maxY == 0) {
//       return _extractAmountSimple(textBlocks);
//     }
//
//     final amountBlocks = textBlocks.where((block) {
//       final blockCenterX = block.boundingBox.x + (block.boundingBox.width / 2);
//       final blockCenterY = block.boundingBox.y + (block.boundingBox.height / 2);
//
//       final regionLeft = 0.6 * maxX;
//       final regionRight = 1.0 * maxX;
//       final regionTop = cropTop * maxY;
//       final regionBottom = cropBottom * maxY;
//
//       return blockCenterX >= regionLeft &&
//              blockCenterX <= regionRight &&
//              blockCenterY >= regionTop &&
//              blockCenterY <= regionBottom;
//     }).toList();
//
//     amountBlocks.sort((a, b) => b.confidence.compareTo(a.confidence));
//
//     for (final block in amountBlocks) {
//       final text = block.text.trim();
//
//       // Look for ₹ symbol followed by numbers
//       final rupeePattern = RegExp(r'₹\s*(\d+(?:[,\.]\d+)*)');
//       final rupeeMatch = rupeePattern.firstMatch(text);
//       if (rupeeMatch != null) {
//         String amount = rupeeMatch.group(1)!.replaceAll(',', '');
//
//         // Remove 7 from start if it's the first digit (rupee symbol misread)
//         if (amount.startsWith('7')) {
//           amount = amount.substring(1);
//         }
//
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue > 0 && numValue < 100000) {
//           return '₹$amount';
//         }
//       }
//
//       // Look for Rs followed by numbers
//       final rsPattern = RegExp(r'Rs\.?\s*(\d+(?:[,\.]\d+)*)');
//       final rsMatch = rsPattern.firstMatch(text);
//       if (rsMatch != null) {
//         String amount = rsMatch.group(1)!.replaceAll(',', '');
//
//         // Remove 7 from start if it's the first digit (rupee symbol misread)
//         if (amount.startsWith('7')) {
//           amount = amount.substring(1);
//         }
//
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue > 0 && numValue < 100000) {
//           return '₹$amount';
//         }
//       }
//     }
//
//     // Second pass: look for ANY numbers in the region (more flexible)
//     for (final block in amountBlocks) {
//       final text = block.text.trim();
//
//       // Look for any numeric patterns - be more flexible
//       final numberPatterns = [
//         RegExp(r'\b(\d{1,6}(?:\.\d{1,2})?)\b'), // Any numbers with optional decimal
//         RegExp(r'(\d+[,\d]*(?:\.\d{1,2})?)')     // Numbers with commas
//       ];
//
//       for (final pattern in numberPatterns) {
//         final match = pattern.firstMatch(text);
//         if (match != null) {
//           String amount = match.group(1)!.replaceAll(',', '');
//
//           // Remove 7 from start if it's the first digit (rupee symbol misread)
//           if (amount.startsWith('7')) {
//             amount = amount.substring(1);
//           }
//
//           final numValue = double.tryParse(amount);
//           if (numValue != null && numValue >= 1 && numValue < 100000) { // Lowered minimum from 10 to 1
//             return '₹$amount';
//           }
//         }
//       }
//     }
//
//     // Third pass: look for numbers anywhere in the text block
//     for (final block in amountBlocks) {
//       final text = block.text.trim();
//
//       // Extract any numbers from the text
//       final allNumbers = RegExp(r'\d+(?:\.\d{1,2})?').allMatches(text);
//       for (final match in allNumbers) {
//         String amount = match.group(0)!;
//
//         // Remove 7 from start if it's the first digit (rupee symbol misread)
//         if (amount.startsWith('7')) {
//           amount = amount.substring(1);
//         }
//
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue >= 1 && numValue < 100000) {
//           return '₹$amount';
//         }
//       }
//     }
//
//     // Fallback: use simple extraction if region-based fails
//     return _extractAmountSimple(textBlocks);
//   }
//
//   /// Simple amount extraction as fallback
//   static String? _extractAmountSimple(List<TextBlock> textBlocks) {
//     for (final block in textBlocks) {
//       final text = block.text.trim();
//
//       // Look for ₹ symbol followed by numbers
//       final rupeePattern = RegExp(r'₹\s*(\d+(?:[,\.]\d+)*)');
//       final rupeeMatch = rupeePattern.firstMatch(text);
//       if (rupeeMatch != null) {
//         final amount = rupeeMatch.group(1)!.replaceAll(',', '');
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue > 0 && numValue < 100000) {
//           return '₹$amount';
//         }
//       }
//
//       // Look for Rs followed by numbers
//       final rsPattern = RegExp(r'Rs\.?\s*(\d+(?:[,\.]\d+)*)');
//       final rsMatch = rsPattern.firstMatch(text);
//       if (rsMatch != null) {
//         final amount = rsMatch.group(1)!.replaceAll(',', '');
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue > 0 && numValue < 100000) {
//           return '₹$amount';
//         }
//       }
//
//       // Look for standalone numbers
//       final numberPattern = RegExp(r'\b(\d{1,5}(?:\.\d{1,2})?)\b');
//       final numberMatch = numberPattern.firstMatch(text);
//       if (numberMatch != null) {
//         String amount = numberMatch.group(1)!;
//
//         // Remove 7 from start if it's the first digit (rupee symbol misread)
//         if (amount.startsWith('7')) {
//           amount = amount.substring(1);
//         }
//
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue > 10 && numValue < 50000) {
//           return '₹$amount';
//         }
//       }
//     }
//     return null;
//   }
//
//
//   /// Extract payee from specific region
//   static String? _extractPayeeFromRegion(List<TextBlock> textBlocks, CropRegion? region) {
//     if (region == null) return null;
//
//     // Find the longest valid text block in the region
//     String? bestCandidate;
//     int maxLength = 0;
//
//     for (final block in textBlocks) {
//       final text = block.text.trim();
//       if (_isValidPayeeName(text) && text.length > maxLength) {
//         bestCandidate = text;
//         maxLength = text.length;
//       }
//     }
//
//     return bestCandidate != null ? _cleanPayeeName(bestCandidate) : null;
//   }
//
//   /// Calculate overall confidence score
//   static double _calculateOverallConfidence(List<String?> fields) {
//     final nonNullFields = fields.where((f) => f != null && f.isNotEmpty).length;
//     return (nonNullFields / fields.length) * 100;
//   }
//
//   /// Fix null comparison warning
//   static String? extractAmount(List<TextBlock> textBlocks, PaymentApp app) {
//     final template = PaymentAppTemplate.getTemplate(app);
//     final amountKeywords = template.fieldKeywords['amount'];
//
//     // Check if keywords exist before using them
//     if (amountKeywords != null) {
//       // Find amount using keywords
//       for (final keyword in amountKeywords) {
//         for (int i = 0; i < textBlocks.length; i++) {
//           final block = textBlocks[i];
//           if (block.text.toLowerCase().contains(keyword.toLowerCase())) {
//             // Look for amount in same block or next few blocks
//             for (int j = i; j < (i + 3).clamp(0, textBlocks.length); j++) {
//               final amountText = textBlocks[j].text;
//               final amount = _extractAmountFromText(amountText);
//               if (amount.isNotEmpty) {
//                 return amount;
//               }
//             }
//           }
//         }
//       }
//     }
//
//     // If no keyword-based amount found, search for currency patterns
//     for (final block in textBlocks) {
//       if (block.text.contains('₹') || block.text.contains('Rs')) {
//         final amount = _extractAmountFromText(block.text);
//         if (amount.isNotEmpty) {
//           return amount;
//         }
//       }
//     }
//
//     return null;
//   }
//
//   /// Extract payee name from text blocks
//   static String? extractPayee(List<TextBlock> textBlocks, PaymentApp app) {
//     final template = PaymentAppTemplate.getTemplate(app);
//     final payeeKeywords = template.fieldKeywords['payee'];
//
//     if (payeeKeywords != null) {
//       for (final keyword in payeeKeywords) {
//         for (int i = 0; i < textBlocks.length; i++) {
//           final block = textBlocks[i];
//           if (block.text.toLowerCase().contains(keyword.toLowerCase())) {
//             // Look for payee in next blocks
//             for (int j = i + 1; j < (i + 3).clamp(0, textBlocks.length); j++) {
//               final payeeText = textBlocks[j].text.trim();
//               if (payeeText.isNotEmpty && _isValidPayeeName(payeeText)) {
//                 return payeeText;
//               }
//             }
//           }
//         }
//       }
//     }
//
//     return null;
//   }
//
//   /// Extract transaction ID using keyword and position heuristics
//   static String? extractTransactionId(List<TextBlock> textBlocks, PaymentApp app) {
//     final template = PaymentAppTemplate.getTemplate(app);
//     final idKeywords = template.fieldKeywords['transactionId'];
//
//     if (idKeywords != null) {
//       for (final keyword in idKeywords) {
//         for (int i = 0; i < textBlocks.length; i++) {
//           final block = textBlocks[i];
//           if (block.text.toLowerCase().contains(keyword.toLowerCase())) {
//             // Look for transaction ID in same or next block
//             for (int j = i; j < (i + 2).clamp(0, textBlocks.length); j++) {
//               final idText = textBlocks[j].text.trim();
//               if (idText.isNotEmpty && _isValidTransactionId(idText)) {
//                 return idText;
//               }
//             }
//           }
//         }
//       }
//     }
//
//     return null;
//   }
//
//   /// Extract amount from text string
//   static String _extractAmountFromText(String text) {
//     // Remove currency symbols and clean the text
//     final cleanText = text
//         .replaceAll('₹', '')
//         .replaceAll('Rs', '')
//         .replaceAll(RegExp(r'[^\d\.,]'), '')
//         .trim();
//
//     if (cleanText.isEmpty) return '';
//
//     // Handle comma separators
//     String normalizedText = cleanText;
//     if (normalizedText.contains(',')) {
//       normalizedText = normalizedText.replaceAll(',', '');
//     }
//
//     // Validate numeric format
//     final amount = double.tryParse(normalizedText);
//     if (amount != null && amount > 0) {
//       return amount.toStringAsFixed(2);
//     }
//
//     return '';
//   }
//
//   /// Validate transaction ID format
//   static bool _isValidTransactionId(String text) {
//     // Remove whitespace and check length
//     final cleanText = text.trim();
//
//     // Transaction ID should be alphanumeric, 6-20 characters
//     if (cleanText.length < 6 || cleanText.length > 20) return false;
//
//     // Should contain at least one number
//     if (!RegExp(r'\d').hasMatch(cleanText)) return false;
//
//     // Should not be just numbers (that's likely an amount)
//     if (RegExp(r'^\d+$').hasMatch(cleanText)) return false;
//
//     // Should contain alphanumeric characters
//     if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(cleanText)) return false;
//
//     return true;
//   }
//
//   /// Extract transaction fields using backward compatibility approach
//   static ExtractedTransaction extractTransactionFields(
//     List<TextBlock> textBlocks,
//     PaymentApp app,
//   ) {
//     // Use the existing extraction methods
//     final amount = extractAmount(textBlocks, app);
//     final payee = extractPayee(textBlocks, app);
//     final transactionId = extractTransactionId(textBlocks, app);
//
//     return ExtractedTransaction(
//       amount: amount,
//       payeeName: payee,
//       date: null, // Date extraction completely removed
//       transactionId: transactionId,
//       confidence: _calculateOverallConfidence([amount, payee, transactionId]),
//     );
//   }
//
//
//   /// Extract payee name using position and keyword heuristics
//   static String? _extractPayee(
//     List<TextBlock> textBlocks, 
//     PaymentAppTemplate template, {
//     double cropTop = 0.17,
//     double cropBottom = 0.21,
//   }) {
//     // For PhonePe: Since the image is cropped to only contain name (left 60%) and amount (right 40%),
//     // we don't need keywords - just extract whatever text is in the left 60%
//     if (template.app == PaymentApp.phonePe) {
//       return _extractPhonePePayee(textBlocks, template, cropTop: cropTop, cropBottom: cropBottom);
//     }
//
//     // Look for text blocks near payee keywords for other apps
//     final payeeKeywords = template.fieldKeywords['payee'] ?? [];
//
//     for (final keyword in payeeKeywords) {
//       for (int i = 0; i < textBlocks.length; i++) {
//         final block = textBlocks[i];
//
//         if (block.text.toLowerCase().contains(keyword.toLowerCase())) {
//           // Look for payee name in next few blocks
//           for (int j = i + 1; j < (i + 3).clamp(0, textBlocks.length); j++) {
//             final candidateBlock = textBlocks[j];
//             final candidateText = candidateBlock.text.trim();
//
//             if (_isValidPayeeName(candidateText)) {
//               return _cleanPayeeName(candidateText);
//             }
//           }
//         }
//       }
//     }
//
//     // Fallback: extract from payee region
//     return _extractPayeeFromRegion(textBlocks, template.fieldRegions['payee']);
//   }
//
//   /// Extract payee specifically from PhonePe's optimized crop region (left 60%)
//   static String? _extractPhonePePayee(
//     List<TextBlock> textBlocks, 
//     PaymentAppTemplate template, {
//     double cropTop = 0.17,
//     double cropBottom = 0.21,
//   }) {
//     // Get image dimensions from text blocks (approximate)
//     double maxX = 0, maxY = 0;
//     for (final block in textBlocks) {
//       final rightX = (block.boundingBox.x + block.boundingBox.width).toDouble();
//       final bottomY = (block.boundingBox.y + block.boundingBox.height).toDouble();
//       if (rightX > maxX) maxX = rightX;
//       if (bottomY > maxY) maxY = bottomY;
//     }
//
//     // If we can't determine image dimensions, take the first valid text block
//     if (maxX == 0 || maxY == 0) {
//       for (final block in textBlocks) {
//         final text = block.text.trim();
//         if (text.isNotEmpty && text.length > 1 && !RegExp(r'^\d+$').hasMatch(text)) {
//           return _cleanPayeeName(text);
//         }
//       }
//       return null;
//     }
//
//     // Filter text blocks that fall within the payee region (left 60% of the strip)
//     final payeeBlocks = textBlocks.where((block) {
//       final blockCenterX = block.boundingBox.x + (block.boundingBox.width / 2);
//       final regionRight = 0.6 * maxX;  // 60% from left (left 60% for payee)
//       return blockCenterX <= regionRight;
//     }).toList();
//
//     // Sort by confidence and take the best text in the payee region
//     payeeBlocks.sort((a, b) => b.confidence.compareTo(a.confidence));
//
//     // Find the best payee candidate in the region
//     for (final block in payeeBlocks) {
//       final text = block.text.trim();
//
//       if (_isValidPayeeName(text)) {
//         return _cleanPayeeName(text);
//       }
//     }
//
//     // Fallback: use keyword-based extraction
//     return _extractPayeeWithKeywords(textBlocks, template);
//   }
//
//   /// Extract payee using keyword-based approach as fallback
//   static String? _extractPayeeWithKeywords(List<TextBlock> textBlocks, PaymentAppTemplate template) {
//     final payeeKeywords = template.fieldKeywords['payee'] ?? [];
//
//     for (final keyword in payeeKeywords) {
//       for (int i = 0; i < textBlocks.length; i++) {
//         final block = textBlocks[i];
//
//         if (block.text.toLowerCase().contains(keyword.toLowerCase())) {
//           // Look for payee name in next few blocks
//           for (int j = i + 1; j < (i + 3).clamp(0, textBlocks.length); j++) {
//             final candidateBlock = textBlocks[j];
//             final candidateText = candidateBlock.text.trim();
//
//             if (_isValidPayeeName(candidateText)) {
//               return _cleanPayeeName(candidateText);
//             }
//           }
//         }
//       }
//     }
//
//     return null;
//   }
//
//
//   /// Check if text is a valid payee name
//   static bool _isValidPayeeName(String text) {
//     // Filter out common non-name patterns
//     if (text.length < 2 || text.length > 50) return false;
//     if (RegExp(r'^\d+$').hasMatch(text)) return false; // Pure numbers
//     if (RegExp(r'^[^\w\s]+$').hasMatch(text)) return false; // Pure symbols
//     if (text.toLowerCase().contains('transaction') ||
//         text.toLowerCase().contains('payment') ||
//         text.toLowerCase().contains('transfer') ||
//         text.toLowerCase().contains('upi') ||
//         text.toLowerCase().contains('phonepe')) {
//       return false;
//     }
//
//     return true;
//   }
//
//   /// Clean and format amount text
//   static String _cleanAmountText(String text) {
//     // Remove currency symbols and extra spaces
//     String cleaned = text
//         .replaceAll('₹', '')
//         .replaceAll('Rs', '')
//         .replaceAll(RegExp(r'[^ -\d\.,]'), '') // Remove non-ASCII except digits, dot, comma
//         .trim();
//
//     // Fix OCR artifact: if starts with '7' and rest is a valid number, and without '7' is plausible, remove '7'
//     if (cleaned.startsWith('7') && cleaned.length > 2) {
//       final possibleAmount = cleaned.substring(1);
//       final numValue = double.tryParse(possibleAmount);
//       // Only replace if the number without '7' is plausible
//       if (numValue != null && numValue > 0 && numValue < 100000) {
//         cleaned = possibleAmount;
//       }
//     }
//
//     // Handle comma separators in Indian format
//     if (cleaned.contains(',')) {
//       cleaned = cleaned.replaceAll(',', '');
//     }
//
//     // Ensure proper decimal format
//     final parts = cleaned.split('.');
//     if (parts.length > 2) {
//       cleaned = '${parts[0]}.${parts[1]}'; // Keep only first decimal
//     }
//
//     return cleaned;
//   }
//
//   /// Clean and format payee name
//   static String _cleanPayeeName(String text) {
//     return text
//         .replaceAll(RegExp(r'[^\w\s\-\.]'), '') // Keep only alphanumeric, spaces, hyphens, dots
//         .replaceAll(RegExp(r'\s+'), ' ') // Normalize spaces
//         .trim();
//   }
//
//   /// Extract payee from left crop using the WORKING logic from GitHub
//   static String? extractPayeeFromLeftCrop(List<TextBlock> textBlocks) {
//     // This is the EXACT working logic from your GitHub version
//     // Find the longest valid text block (simple approach that worked)
//     String? bestCandidate;
//     int maxLength = 0;
//
//     for (final block in textBlocks) {
//       final text = block.text.trim();
//       if (_isValidPayeeName(text) && text.length > maxLength) {
//         bestCandidate = text;
//         maxLength = text.length;
//       }
//     }
//
//     return bestCandidate != null ? _cleanPayeeName(bestCandidate) : null;
//   }
//
//   /// Extract amount from right crop using CURRENT enhanced logic with "7" fix
//   static String? extractAmountFromRightCrop(List<TextBlock> textBlocks) {
//     if (textBlocks.isEmpty) {
//       return null;
//     }
//
//     // Sort by confidence first
//     final sortedBlocks = List<TextBlock>.from(textBlocks);
//     sortedBlocks.sort((a, b) => b.confidence.compareTo(a.confidence));
//
//     // First pass: look for currency symbols
//     for (final block in sortedBlocks) {
//       final text = block.text.trim();
//
//       // Look for ₹ symbol followed by numbers
//       final rupeePattern = RegExp(r'₹\s*(\d+(?:[,\.]\d+)*)');
//       final rupeeMatch = rupeePattern.firstMatch(text);
//       if (rupeeMatch != null) {
//         String amount = rupeeMatch.group(1)!.replaceAll(',', '');
//
//         // Remove 7 from start if it's the first digit (rupee symbol misread)
//         if (amount.startsWith('7')) {
//           amount = amount.substring(1);
//         }
//
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue > 0 && numValue < 100000) {
//           return '₹$amount';
//         }
//       }
//
//       // Look for Rs followed by numbers
//       final rsPattern = RegExp(r'Rs\.?\s*(\d+(?:[,\.]\d+)*)');
//       final rsMatch = rsPattern.firstMatch(text);
//       if (rsMatch != null) {
//         String amount = rsMatch.group(1)!.replaceAll(',', '');
//
//         // Remove 7 from start if it's the first digit (rupee symbol misread)
//         if (amount.startsWith('7')) {
//           amount = amount.substring(1);
//         }
//
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue > 0 && numValue < 100000) {
//           return '₹$amount';
//         }
//       }
//     }
//
//     // Second pass: look for ANY numbers with flexible patterns
//     for (final block in sortedBlocks) {
//       final text = block.text.trim();
//
//       final numberPatterns = [
//         RegExp(r'(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?)'),  // Numbers with proper comma formatting (1,000, 2,000)
//         RegExp(r'(\d+[,\d]*(?:\.\d{1,2})?)'),  // Any numbers with commas
//         RegExp(r'\b(\d{1,6}(?:\.\d{1,2})?)\b')  // Standalone numbers
//       ];
//
//       for (int i = 0; i < numberPatterns.length; i++) {
//         final pattern = numberPatterns[i];
//         final match = pattern.firstMatch(text);
//         if (match != null) {
//           String amount = match.group(1)!.replaceAll(',', '');
//
//           // Remove 7 from start if it's the first digit (rupee symbol misread)
//           if (amount.startsWith('7')) {
//             amount = amount.substring(1);
//           }
//
//           final numValue = double.tryParse(amount);
//           if (numValue != null && numValue >= 1 && numValue < 100000) {
//             return '₹$amount';
//           }
//         }
//       }
//     }
//
//     // Third pass: extract any numbers and apply "7" prefix fix
//     for (final block in sortedBlocks) {
//       final text = block.text.trim();
//       final allNumbers = RegExp(r'\d+(?:\.\d{1,2})?').allMatches(text);
//
//       for (final match in allNumbers) {
//         String amount = match.group(0)!;
//
//         // Remove 7 from start if it's the first digit (rupee symbol misread)
//         if (amount.startsWith('7')) {
//           amount = amount.substring(1);
//         }
//
//         final numValue = double.tryParse(amount);
//         if (numValue != null && numValue >= 1 && numValue < 100000) {
//           return '₹$amount';
//         }
//       }
//     }
//
//     return null;
//   }
// }
