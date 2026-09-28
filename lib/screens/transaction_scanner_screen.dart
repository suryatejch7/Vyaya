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
// import 'package:image_picker/image_picker.dart';
// import 'package:provider/provider.dart';
// import '../models/transaction_ocr_models.dart';
// import '../services/transaction_processing_service.dart';
// import '../screens/add_expense_screen.dart';
// import '../providers/user_provider.dart';
//
// class TransactionScannerScreen extends StatefulWidget {
//   final File? initialImage;
//
//   const TransactionScannerScreen({super.key, this.initialImage});
//
//   @override
//   State<TransactionScannerScreen> createState() => _TransactionScannerScreenState();
// }
//
// class _TransactionScannerScreenState extends State<TransactionScannerScreen> {
//   File? _selectedImage;
//   PaymentApp? _selectedApp;
//   bool _isProcessing = false;
//   ExtractedTransaction? _extractedData;
//   String? _errorMessage;
//   double _processingProgress = 0.0;
//   List<String> _processingSteps = [];
//
//   final ImagePicker _imagePicker = ImagePicker();
//
//   @override
//   void initState() {
//     super.initState();
//     if (widget.initialImage != null) {
//       _selectedImage = widget.initialImage;
//       _selectedApp = PaymentApp.phonePe;
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         _processTransaction();
//       });
//     }
//   }
//
//   @override
//   void dispose() {
//     // Clean up shared images from the intent cache
//     _cleanupSharedImage();
//     super.dispose();
//   }
//
//   Future<void> _cleanupSharedImage() async {
//     // Only clean up images that came from sharing intent (not gallery picks)
//     if (widget.initialImage == null) return;
//     try {
//       final file = widget.initialImage!;
//       if (await file.exists()) {
//         await file.delete();
//       }
//     } catch (_) {
//       // Best-effort cleanup
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black,
//       appBar: AppBar(
//         title: const Text(
//           'Scan PhonePe Receipt',
//           style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
//         ),
//         backgroundColor: Colors.black,
//         elevation: 0,
//         iconTheme: const IconThemeData(color: Colors.white),
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             _buildImageSection(),
//             const SizedBox(height: 24),
//             _buildProcessingSection(),
//             if (_processingSteps.isNotEmpty) ...[
//               const SizedBox(height: 24),
//               _buildProcessingStepsSection(),
//             ],
//             if (_extractedData != null) ...[
//               const SizedBox(height: 24),
//               _buildExtractedDataSection(),
//             ],
//             if (_errorMessage != null) ...[
//               const SizedBox(height: 24),
//               _buildErrorSection(),
//             ],
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildImageSection() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: const Color(0xFF1A1A1A),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Transaction Screenshot',
//             style: TextStyle(
//               color: Colors.white,
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//           const SizedBox(height: 16),
//           if (_selectedImage == null) ...[
//             GestureDetector(
//               onTap: _showImageSourceDialog,
//               child: Container(
//                 height: 200,
//                 width: double.infinity,
//                 decoration: BoxDecoration(
//                   color: const Color(0xFF2A2A2A),
//                   borderRadius: BorderRadius.circular(12),
//                   border: Border.all(
//                     color: Colors.grey.withValues(alpha: 0.3),
//                     style: BorderStyle.solid,
//                   ),
//                 ),
//                 child: const Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Icon(
//                       Icons.add_photo_alternate,
//                       color: Colors.grey,
//                       size: 48,
//                     ),
//                     SizedBox(height: 12),
//                     Text(
//                       'Tap to select transaction screenshot',
//                       style: TextStyle(
//                         color: Colors.grey,
//                         fontSize: 16,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ] else ...[
//             ClipRRect(
//               borderRadius: BorderRadius.circular(12),
//               child: Image.file(
//                 _selectedImage!,
//                 height: 200,
//                 width: double.infinity,
//                 fit: BoxFit.cover,
//               ),
//             ),
//             const SizedBox(height: 12),
//             Row(
//               children: [
//                 Expanded(
//                   child: ElevatedButton.icon(
//                     onPressed: _showImageSourceDialog,
//                     icon: const Icon(Icons.refresh),
//                     label: const Text('Change Image'),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: const Color(0xFF2A2A2A),
//                       foregroundColor: Colors.white,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 12),
//                 ElevatedButton.icon(
//                   onPressed: () {
//                     setState(() {
//                       _selectedImage = null;
//                       _extractedData = null;
//                       _errorMessage = null;
//                       _processingSteps = [];
//                     });
//                   },
//                   icon: const Icon(Icons.delete),
//                   label: const Text('Remove'),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.red.withValues(alpha: 0.2),
//                     foregroundColor: Colors.red,
//                   ),
//                 ),
//               ],
//             ),
//           ],
//         ],
//       ),
//     );
//   }
//
//   Widget _buildProcessingSection() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: const Color(0xFF1A1A1A),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Process Transaction',
//             style: TextStyle(
//               color: Colors.white,
//               fontSize: 18,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//           const SizedBox(height: 16),
//           if (_isProcessing) ...[
//             LinearProgressIndicator(
//               value: _processingProgress,
//               backgroundColor: Colors.grey.withValues(alpha: 0.3),
//               valueColor: AlwaysStoppedAnimation<Color>(
//                 Theme.of(context).colorScheme.primary,
//               ),
//             ),
//             const SizedBox(height: 12),
//             Text(
//               '${(_processingProgress * 100).toStringAsFixed(0)}% - Processing transaction data...',
//               style: const TextStyle(
//                 color: Colors.grey,
//                 fontSize: 14,
//               ),
//             ),
//           ] else ...[
//             ElevatedButton.icon(
//               onPressed: _canProcess() ? _processTransaction : null,
//               icon: const Icon(Icons.document_scanner),
//               label: const Text('Extract Transaction Data'),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: Theme.of(context).colorScheme.primary,
//                 foregroundColor: Colors.white,
//                 minimumSize: const Size(double.infinity, 48),
//               ),
//             ),
//           ],
//           const SizedBox(height: 12),
//           Text(
//             _canProcess()
//                 ? 'Ready to process PhonePe receipt'
//                 : 'Select PhonePe receipt image to continue',
//             style: const TextStyle(
//               color: Colors.grey,
//               fontSize: 12,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildProcessingStepsSection() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: const Color(0xFF1A1A1A),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Icon(
//                 Icons.settings,
//                 color: Colors.blue,
//                 size: 20,
//               ),
//               const SizedBox(width: 8),
//               const Text(
//                 'Processing Steps',
//                 style: TextStyle(
//                   color: Colors.white,
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 12),
//           ..._processingSteps.map((step) => Padding(
//             padding: const EdgeInsets.symmetric(vertical: 4),
//             child: Row(
//               children: [
//                 Icon(
//                   Icons.check_circle,
//                   color: Colors.green,
//                   size: 16,
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   child: Text(
//                     step,
//                     style: const TextStyle(
//                       color: Colors.grey,
//                       fontSize: 14,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           )),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildExtractedDataSection() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: const Color(0xFF1A1A1A),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Icon(
//                 Icons.check_circle,
//                 color: Colors.green,
//                 size: 20,
//               ),
//               const SizedBox(width: 8),
//               const Text(
//                 'Extracted Data',
//                 style: TextStyle(
//                   color: Colors.white,
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const Spacer(),
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                 decoration: BoxDecoration(
//                   color: Colors.green.withValues(alpha: 0.2),
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: Text(
//                   '${_extractedData!.confidence.toStringAsFixed(0)}%',
//                   style: const TextStyle(
//                     color: Colors.green,
//                     fontSize: 12,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 16),
//           _buildDataField('Amount', _extractedData!.amount ?? 'Not found'),
//           _buildDataField('Payee', _extractedData!.payeeName ?? 'Not found'),
//           _buildDataField('Date', _extractedData!.date ?? 'Not found'),
//           const SizedBox(height: 16),
//           Row(
//             children: [
//               Expanded(
//                 child: ElevatedButton.icon(
//                   onPressed: _addToExpenses,
//                   icon: const Icon(Icons.add),
//                   label: const Text('Add to Expenses'),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.green,
//                     foregroundColor: Colors.white,
//                   ),
//                 ),
//               ),
//               const SizedBox(width: 12),
//               ElevatedButton.icon(
//                 onPressed: _editTransaction,
//                 icon: const Icon(Icons.edit),
//                 label: const Text('Edit'),
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: const Color(0xFF2A2A2A),
//                   foregroundColor: Colors.white,
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildDataField(String label, String value) {
//     final isFound = value != 'Not found';
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 6),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           SizedBox(
//             width: 80,
//             child: Text(
//               '$label:',
//               style: const TextStyle(
//                 color: Colors.grey,
//                 fontSize: 14,
//                 fontWeight: FontWeight.w500,
//               ),
//             ),
//           ),
//           Expanded(
//             child: Text(
//               value,
//               style: TextStyle(
//                 color: isFound ? Colors.white : Colors.red,
//                 fontSize: 14,
//                 fontWeight: isFound ? FontWeight.w600 : FontWeight.normal,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildErrorSection() {
//     return Container(
//       width: double.infinity,
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: const Color(0xFF1A1A1A),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Icon(
//                 Icons.error,
//                 color: Colors.red,
//                 size: 20,
//               ),
//               const SizedBox(width: 8),
//               const Text(
//                 'Processing Error',
//                 style: TextStyle(
//                   color: Colors.white,
//                   fontSize: 18,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 12),
//           Text(
//             _errorMessage!,
//             style: const TextStyle(
//               color: Colors.red,
//               fontSize: 14,
//             ),
//           ),
//           const SizedBox(height: 16),
//           ElevatedButton.icon(
//             onPressed: _processTransaction,
//             icon: const Icon(Icons.refresh),
//             label: const Text('Try Again'),
//             style: ElevatedButton.styleFrom(
//               backgroundColor: Colors.red.withValues(alpha: 0.2),
//               foregroundColor: Colors.red,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   /// Show dialog to select image source
//   Future<void> _showImageSourceDialog() async {
//     final source = await showDialog<ImageSource>(
//       context: context,
//       builder: (context) => AlertDialog(
//         backgroundColor: const Color(0xFF1A1A1A),
//         title: const Text(
//           'Select Image Source',
//           style: TextStyle(color: Colors.white),
//         ),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             ListTile(
//               leading: const Icon(Icons.camera_alt, color: Colors.blue),
//               title: const Text('Camera', style: TextStyle(color: Colors.white)),
//               onTap: () => Navigator.of(context).pop(ImageSource.camera),
//             ),
//             ListTile(
//               leading: const Icon(Icons.photo_library, color: Colors.green),
//               title: const Text('Gallery', style: TextStyle(color: Colors.white)),
//               onTap: () => Navigator.of(context).pop(ImageSource.gallery),
//             ),
//           ],
//         ),
//       ),
//     );
//
//     if (source != null) {
//       final pickedFile = await _imagePicker.pickImage(source: source);
//       if (pickedFile != null) {
//         setState(() {
//           _selectedImage = File(pickedFile.path);
//           _selectedApp = PaymentApp.phonePe; // Automatically set PhonePe
//           _extractedData = null;
//           _errorMessage = null;
//           _processingSteps = [];
//         });
//
//         // Automatically start processing when image is selected
//         _processTransaction();
//       }
//     }
//   }
//
//   bool _canProcess() {
//     return _selectedImage != null && _selectedApp != null && !_isProcessing;
//   }
//
//   Future<void> _processTransaction() async {
//     if (!_canProcess()) return;
//
//     setState(() {
//       _isProcessing = true;
//       _processingProgress = 0.0;
//       _extractedData = null;
//       _errorMessage = null;
//       _processingSteps = [];
//     });
//
//     try {
//       // Get user's crop settings from UserProvider
//       final userProvider = context.read<UserProvider>();
//       final userSettings = userProvider.userSettings;
//
//       ProcessingResult result;
//       if (userSettings != null && userSettings.isCropCalibrated) {
//         // Use user's calibrated crop settings
//         result = await TransactionProcessingService.processTransactionScreenshotWithUserSettings(
//           _selectedImage!,
//           userSettings,
//           onProgress: (progress) {
//             setState(() {
//               _processingProgress = progress;
//             });
//           },
//         );
//       } else {
//         // Use default crop settings (your working values)
//         result = await TransactionProcessingService.processTransactionScreenshot(
//           _selectedImage!,
//           onProgress: (progress) {
//             setState(() {
//               _processingProgress = progress;
//             });
//           },
//         );
//       }
//
//       setState(() {
//         _isProcessing = false;
//         _processingProgress = 1.0;
//         _processingSteps = result.processingSteps;
//       });
//
//       if (result.success) {
//         setState(() {
//           _extractedData = result.extractedTransaction;
//         });
//
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text(
//                 '✅ Extraction complete! Navigating to Add Expense...'
//               ),
//               backgroundColor: Colors.green,
//               duration: Duration(seconds: 1),
//             ),
//           );
//
//           // Wait briefly then auto-navigate to Add Expense
//           await Future.delayed(Duration(milliseconds: 800));
//
//           if (mounted) {
//             final result = await Navigator.of(context).push(
//               MaterialPageRoute(
//                 builder: (context) => AddExpenseScreen(
//                   prefilledAmount: double.tryParse(_extractedData!.amount?.replaceAll(RegExp(r'[^\d.]'), '') ?? '0') ?? 0.0,
//                   prefilledPayee: _extractedData!.payeeName,
//                   prefilledPaymentApp: _selectedApp?.displayName,
//                   prefilledTransactionId: _extractedData!.transactionId,
//                   extractedData: _extractedData,
//                 ),
//               ),
//             );
//
//             // If expense was saved successfully, show confirmation and go back
//             if (result == true) {
//               if (mounted) {
//                 ScaffoldMessenger.of(context).showSnackBar(
//                   const SnackBar(
//                     content: Text('✅ Expense saved successfully!'),
//                     backgroundColor: Colors.green,
//                     duration: Duration(seconds: 1),
//                   ),
//                 );
//
//                 // Go back to previous screen or clear data for next transaction
//                 Navigator.pop(context);
//               }
//             }
//           }
//         }
//       } else {
//         setState(() {
//           _errorMessage = result.error ?? 'Unknown processing error';
//         });
//       }
//     } catch (e) {
//       setState(() {
//         _isProcessing = false;
//         _errorMessage = 'Failed to process transaction: $e';
//         _processingSteps = [
//           'Processing started...',
//           'Image loaded successfully',
//           'Error occurred during OCR processing',
//           'Error: ${e.toString()}'
//         ];
//       });
//
//       // Show error message to user
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('❌ OCR processing failed. You can still add the transaction manually.'),
//             backgroundColor: Colors.red,
//             duration: Duration(seconds: 1),
//           ),
//         );
//       }
//     }
//   }
//
//
//   void _addToExpenses() async {
//     if (_extractedData == null) return;
//
//     try {
//       // Show loading dialog
//       showDialog(
//         context: context,
//         barrierDismissible: false,
//         builder: (context) => const AlertDialog(
//           backgroundColor: Color(0xFF1A1A1A),
//           content: Row(
//             children: [
//               CircularProgressIndicator(),
//               SizedBox(width: 16),
//               Text('Saving expense...', style: TextStyle(color: Colors.white)),
//             ],
//           ),
//         ),
//       );
//
//       // Navigate to add expense screen with pre-filled data
//       Navigator.pop(context); // Close loading dialog
//
//       final result = await Navigator.of(context).push(
//         MaterialPageRoute(
//           builder: (context) => AddExpenseScreen(
//             prefilledAmount: double.tryParse(_extractedData!.amount?.replaceAll(RegExp(r'[^\d.]'), '') ?? '0') ?? 0.0,
//             prefilledPayee: _extractedData!.payeeName,
//             prefilledPaymentApp: _selectedApp?.displayName,
//             prefilledTransactionId: _extractedData!.transactionId,
//             extractedData: _extractedData,
//           ),
//         ),
//       );
//
//       // If expense was saved successfully, show confirmation
//       if (result == true) {
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(
//               content: Text('✅ Expense saved successfully!'),
//               backgroundColor: Colors.green,
//               duration: Duration(seconds: 1),
//             ),
//           );
//
//           // Clear the current transaction data
//           setState(() {
//             _selectedImage = null;
//             _extractedData = null;
//             _errorMessage = null;
//             _processingSteps = [];
//             _selectedApp = null;
//           });
//         }
//       }
//     } catch (e) {
//       if (mounted) {
//         Navigator.pop(context); // Close loading dialog if open
//
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('❌ Failed to save expense: $e'),
//             backgroundColor: Colors.red,
//             duration: Duration(seconds: 1),
//           ),
//         );
//       }
//     }
//   }
//
//   /// Edit extracted transaction data
//   void _editTransaction() {
//     // Navigate to edit screen or show edit dialog
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         backgroundColor: const Color(0xFF1A1A1A),
//         title: const Text(
//           'Edit Transaction Data',
//           style: TextStyle(color: Colors.white),
//         ),
//         content: const Text(
//           'Manual editing functionality coming soon!',
//           style: TextStyle(color: Colors.grey),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.of(context).pop(),
//             child: const Text('OK'),
//           ),
//         ],
//       ),
//     );
//   }
// }