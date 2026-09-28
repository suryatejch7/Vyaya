// ============================================================================
// SCREENSHOT SCANNING (ML Kit OCR) IS DISABLED
// Vyaya ships fully offline with no internet permission. Google ML Kit adds
// the INTERNET permission and Google usage reporting, so everything used only
// by screenshot scanning is commented out rather than deleted.
// To turn it back on, follow "Re-enabling screenshot scanning" in README.md
// (in each file: select everything below this header and press Ctrl+/).
// ============================================================================
// import 'package:intl/intl.dart';
// import '../models/transaction_ocr_models.dart';
//
// /// Service for post-OCR text normalization and field extraction
// class TextNormalizationService {
//   /// Comprehensive text correction mapping for common OCR errors
//   static final Map<String, String> _symbolCorrections = {
//     // Currency symbol corrections
//     '7': '₹', 'T': '₹', 'F': '₹', 'Z': '7', 'S': '5',
//     'O': '0', 'I': '1', 'l': '1', 'g': '9', 'G': '6',
//     'B': '8', 'D': '0', 'Q': '0', 'U': '0',
//
//     // Common digit confusions
//     '§': '5', '€': 'E', '£': 'E', '@': 'a', '#': 'H',
//
//     // Punctuation corrections
//     ';': ':', '|': 'I', '\\': '/',
//   };
//
//   /// Normalize amount text
//   static String? normalizeAmount(String? rawAmount) {
//     if (rawAmount == null || rawAmount.isEmpty) return null;
//
//     try {
//       // Apply symbol corrections
//       String corrected = _applySymbolCorrections(rawAmount);
//
//       // Remove currency symbols and extract numeric value
//       corrected = corrected
//           .replaceAll('₹', '')
//           .replaceAll('Rs', '')
//           .replaceAll('INR', '')
//           .replaceAll(RegExp(r'[^\d\.,]'), '')
//           .trim();
//
//       // Handle Indian number format (lakhs/crores)
//       if (corrected.contains(',')) {
//         corrected = corrected.replaceAll(',', '');
//       }
//
//       // Validate numeric format
//       final amount = double.tryParse(corrected);
//       if (amount == null || amount <= 0) return null;
//
//       return amount.toStringAsFixed(2);
//     } catch (e) {
//       return null;
//     }
//   }
//
//   /// Normalize payee name
//   static String? normalizePayeeName(String? rawPayee) {
//     if (rawPayee == null || rawPayee.isEmpty) return null;
//
//     try {
//       String normalized = _applySymbolCorrections(rawPayee);
//
//       // Remove common prefixes/suffixes
//       normalized = normalized
//           .replaceAll(RegExp(r'^(To|Paid to|Sent to|Recipient):?\s*', caseSensitive: false), '')
//           .replaceAll(RegExp(r'\s*(UPI|IMPS|NEFT).*$', caseSensitive: false), '')
//           .trim();
//
//       // Remove transaction IDs and numbers
//       normalized = normalized.replaceAll(RegExp(r'\b\d{10,}\b'), '').trim();
//
//       // Capitalize properly
//       normalized = _capitalizeName(normalized);
//
//       return normalized.isNotEmpty ? normalized : null;
//     } catch (e) {
//       return null;
//     }
//   }
//
//   /// Normalize date string
//   static String? normalizeDate(String? rawDate) {
//     if (rawDate == null || rawDate.isEmpty) return null;
//
//     try {
//       String corrected = _applySymbolCorrections(rawDate);
//
//       // List of supported date formats
//       final formats = [
//         'dd/MM/yyyy', 'dd-MM-yyyy', 'dd.MM.yyyy',
//         'dd/MM/yy', 'dd-MM-yy', 'dd.MM.yy',
//         'MMM dd, yyyy', 'MMM dd yyyy',
//         'dd MMM yyyy', 'dd MMM, yyyy',
//         'yyyy-MM-dd', 'yyyy/MM/dd',
//       ];
//
//       for (final format in formats) {
//         try {
//           final dateFormat = DateFormat(format);
//           final parsed = dateFormat.parseStrict(corrected);
//
//           // Handle 2-digit years
//           if (parsed.year < 100) {
//             return DateTime(2000 + parsed.year, parsed.month, parsed.day).toIso8601String().split('T')[0];
//           }
//
//           return parsed.toIso8601String().split('T')[0];
//         } catch (e) {
//           continue;
//         }
//       }
//
//       return null;
//     } catch (e) {
//       return null;
//     }
//   }
//
//   /// Apply symbol corrections to text
//   static String _applySymbolCorrections(String text) {
//     String corrected = text;
//
//     for (final entry in _symbolCorrections.entries) {
//       corrected = corrected.replaceAll(entry.key, entry.value);
//     }
//
//     return corrected;
//   }
//
//   /// Capitalize name properly
//   static String _capitalizeName(String name) {
//     return name.split(' ')
//         .map((word) => word.isNotEmpty
//             ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
//             : word)
//         .join(' ');
//   }
//
//   /// Extract and validate transaction amount from text
//   static double? extractAmount(String text) {
//     final amountPattern = RegExp(r'₹?\s*(\d+(?:,\d+)*(?:\.\d{2})?)', caseSensitive: false);
//     final match = amountPattern.firstMatch(text);
//
//     if (match != null) {
//       final amountStr = match.group(1)?.replaceAll(',', '');
//       return double.tryParse(amountStr ?? '');
//     }
//
//     return null;
//   }
//
//   /// Extract date from text using multiple patterns
//   static DateTime? extractDate(String text) {
//     final datePatterns = [
//       RegExp(r'\b(\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4})\b'),
//       RegExp(r'\b(\d{1,2}\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{2,4})\b', caseSensitive: false),
//       RegExp(r'\b((Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},?\s+\d{2,4})\b', caseSensitive: false),
//     ];
//
//     for (final pattern in datePatterns) {
//       final match = pattern.firstMatch(text);
//       if (match != null) {
//         final dateStr = normalizeDate(match.group(1));
//         if (dateStr != null) {
//           return DateTime.tryParse(dateStr);
//         }
//       }
//     }
//
//     return null;
//   }
//
//   /// Extract payee name from text using context clues
//   static String? extractPayeeName(String text, PaymentApp app) {
//     final template = PaymentAppTemplate.getTemplate(app);
//     final keywords = template.fieldKeywords['payee'] ?? [];
//
//     for (final keyword in keywords) {
//       final pattern = RegExp('$keyword[:\\s]+([^\\n\\r]+)', caseSensitive: false);
//       final match = pattern.firstMatch(text);
//
//       if (match != null) {
//         final payee = normalizePayeeName(match.group(1));
//         if (payee != null && payee.isNotEmpty) {
//           return payee;
//         }
//       }
//     }
//
//     return null;
//   }
// }
//
// /// Generic processing result wrapper
// class ProcessingResult<T> {
//   final bool success;
//   final T? data;
//   final List<String> errors;
//   final String? message;
//
//   ProcessingResult({
//     required this.success,
//     this.data,
//     this.errors = const [],
//     this.message,
//   });
//
//   factory ProcessingResult.success(T data, {String? message}) {
//     return ProcessingResult(
//       success: true,
//       data: data,
//       message: message,
//     );
//   }
//
//   factory ProcessingResult.failure(List<String> errors, {String? message}) {
//     return ProcessingResult(
//       success: false,
//       errors: errors,
//       message: message,
//     );
//   }
// }
