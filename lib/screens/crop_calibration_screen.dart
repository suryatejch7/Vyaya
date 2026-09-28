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
// import 'package:image/image.dart' as img;
// import '../providers/user_provider.dart';
//
// class CropCalibrationScreen extends StatefulWidget {
//   const CropCalibrationScreen({super.key});
//
//   @override
//   State<CropCalibrationScreen> createState() => _CropCalibrationScreenState();
// }
//
// class _CropCalibrationScreenState extends State<CropCalibrationScreen> {
//   File? _selectedImage;
//   double _cropTop = 0.17; // Default to your working values
//   double _cropBottom = 0.21; // Default to your working values
//   bool _isLoading = false;
//   bool _isCalibrated = false;
//   File? _croppedPreviewImage;
//   final ImagePicker _picker = ImagePicker();
//
//   @override
//   void initState() {
//     super.initState();
//     _loadCurrentSettings();
//   }
//
//   void _loadCurrentSettings() {
//     final userProvider = context.read<UserProvider>();
//     if (userProvider.userSettings != null) {
//       setState(() {
//         _cropTop = userProvider.userSettings!.cropTop;
//         _cropBottom = userProvider.userSettings!.cropBottom;
//         _isCalibrated = userProvider.userSettings!.isCropCalibrated;
//       });
//     }
//   }
//
//   Future<void> _pickImage() async {
//     try {
//       final XFile? image = await _picker.pickImage(
//         source: ImageSource.gallery,
//         maxWidth: 1920,
//         maxHeight: 1080,
//         imageQuality: 85,
//       );
//
//       if (image != null) {
//         setState(() {
//           _selectedImage = File(image.path);
//         });
//         _generateCroppedPreview();
//       }
//     } catch (e) {
//       _showErrorSnackBar('Failed to pick image: $e');
//     }
//   }
//
//   void _showErrorSnackBar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.red,
//         duration: Duration(seconds: 1),
//       ),
//     );
//   }
//
//   void _showSuccessSnackBar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Theme.of(context).colorScheme.primary,
//         duration: Duration(seconds: 1),
//       ),
//     );
//   }
//
//   Future<void> _saveCropSettings() async {
//     if (_cropTop >= _cropBottom) {
//       _showErrorSnackBar('Top crop must be less than bottom crop');
//       return;
//     }
//
//     setState(() {
//       _isLoading = true;
//     });
//
//     try {
//       final userProvider = context.read<UserProvider>();
//       if (userProvider.userSettings != null) {
//         final updatedSettings = userProvider.userSettings!.copyWith(
//           cropTop: _cropTop,
//           cropBottom: _cropBottom,
//           isCropCalibrated: true,
//           updatedAt: DateTime.now(),
//         );
//
//         await userProvider.updateUserSettings(updatedSettings);
//
//         setState(() {
//           _isCalibrated = true;
//         });
//
//         _showSuccessSnackBar('Crop settings saved successfully!');
//       }
//     } catch (e) {
//       _showErrorSnackBar('Failed to save settings: $e');
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }
//
//   void _resetToDefaults() {
//     setState(() {
//       _cropTop = 0.17;
//       _cropBottom = 0.21;
//       _isCalibrated = false;
//     });
//     _generateCroppedPreview();
//   }
//
//   Future<void> _generateCroppedPreview() async {
//     if (_selectedImage == null) return;
//
//     try {
//       // Read the original image
//       final bytes = await _selectedImage!.readAsBytes();
//       final originalImage = img.decodeImage(bytes);
//
//       if (originalImage == null) return;
//
//       // Calculate crop dimensions
//       final cropY = (originalImage.height * _cropTop).round();
//       final cropHeight = (originalImage.height * (_cropBottom - _cropTop)).round();
//
//       // Create the cropped image
//       final croppedImage = img.copyCrop(
//         originalImage,
//         x: 0,
//         y: cropY,
//         width: originalImage.width,
//         height: cropHeight,
//       );
//
//       // Save the cropped preview
//       final previewPath = '${_selectedImage!.parent.path}/crop_preview_${DateTime.now().millisecondsSinceEpoch}.png';
//       final previewFile = File(previewPath);
//       await previewFile.writeAsBytes(img.encodePng(croppedImage));
//
//       setState(() {
//         _croppedPreviewImage = previewFile;
//       });
//     } catch (e) {
//       // Error generating crop preview - ignore
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFF0A0A0A),
//       appBar: AppBar(
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         title: const Text(
//           'Crop Calibration',
//           style: TextStyle(
//             color: Colors.white,
//             fontWeight: FontWeight.w600,
//           ),
//         ),
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back, color: Colors.white),
//           onPressed: () => Navigator.pop(context),
//         ),
//         actions: [
//           if (_isCalibrated)
//             IconButton(
//               icon: const Icon(Icons.check_circle, color: Colors.green),
//               onPressed: null,
//               tooltip: 'Calibrated',
//             ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Header Section
//             Container(
//               padding: const EdgeInsets.all(20),
//               decoration: BoxDecoration(
//                 color: Colors.white.withValues(alpha: 0.05),
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(
//                   color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
//                 ),
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Row(
//                     children: [
//                       Icon(
//                         Icons.crop_free,
//                         color: Theme.of(context).colorScheme.primary,
//                         size: 24,
//                       ),
//                       const SizedBox(width: 12),
//                       const Text(
//                         'PhonePe Crop Calibration',
//                         style: TextStyle(
//                           color: Colors.white,
//                           fontSize: 18,
//                           fontWeight: FontWeight.w600,
//                         ),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 12),
//                   Text(
//                     'Calibrate the crop area for your PhonePe screenshots to ensure accurate OCR extraction of payee names and amounts.',
//                     style: TextStyle(
//                       color: Colors.white.withValues(alpha: 0.7),
//                       fontSize: 14,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//
//             const SizedBox(height: 24),
//
//             // Image Selection Section
//             Container(
//               padding: const EdgeInsets.all(20),
//               decoration: BoxDecoration(
//                 color: Colors.white.withValues(alpha: 0.05),
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(
//                   color: Colors.white.withValues(alpha: 0.1),
//                 ),
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   const Text(
//                     '1. Select PhonePe Screenshot',
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 16,
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                   const SizedBox(height: 12),
//                   if (_selectedImage == null) ...[
//                     GestureDetector(
//                       onTap: _pickImage,
//                       child: Container(
//                         width: double.infinity,
//                         height: 120,
//                         decoration: BoxDecoration(
//                           color: Colors.white.withValues(alpha: 0.05),
//                           borderRadius: BorderRadius.circular(12),
//                           border: Border.all(
//                             color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
//                             style: BorderStyle.solid,
//                           ),
//                         ),
//                         child: Column(
//                           mainAxisAlignment: MainAxisAlignment.center,
//                           children: [
//                             Icon(
//                               Icons.add_photo_alternate_outlined,
//                               color: Theme.of(context).colorScheme.primary,
//                               size: 32,
//                             ),
//                             const SizedBox(height: 8),
//                             Text(
//                               'Tap to select PhonePe screenshot',
//                               style: TextStyle(
//                                 color: Colors.white.withValues(alpha: 0.7),
//                                 fontSize: 14,
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                   ] else ...[
//                     Container(
//                       width: double.infinity,
//                       height: 200,
//                       decoration: BoxDecoration(
//                         borderRadius: BorderRadius.circular(12),
//                         border: Border.all(
//                           color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
//                         ),
//                       ),
//                       child: ClipRRect(
//                         borderRadius: BorderRadius.circular(12),
//                         child: Image.file(
//                           _selectedImage!,
//                           fit: BoxFit.contain,
//                         ),
//                       ),
//                     ),
//                     const SizedBox(height: 12),
//                     Row(
//                       children: [
//                         Expanded(
//                           child: OutlinedButton.icon(
//                             onPressed: _pickImage,
//                             icon: const Icon(Icons.refresh, size: 18),
//                             label: const Text('Change Image'),
//                             style: OutlinedButton.styleFrom(
//                               foregroundColor: Colors.white,
//                               side: BorderSide(
//                                 color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
//                               ),
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ],
//               ),
//             ),
//
//             const SizedBox(height: 24),
//
//             // Crop Settings Section
//             Container(
//               padding: const EdgeInsets.all(20),
//               decoration: BoxDecoration(
//                 color: Colors.white.withValues(alpha: 0.05),
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(
//                   color: Colors.white.withValues(alpha: 0.1),
//                 ),
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   const Text(
//                     '2. Adjust Crop Area',
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 16,
//                       fontWeight: FontWeight.w600,
//                     ),
//                   ),
//                   const SizedBox(height: 16),
//
//                   // Top Crop Slider
//                   Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           const Text(
//                             'Top Crop',
//                             style: TextStyle(color: Colors.white, fontSize: 14),
//                           ),
//                           Text(
//                             '${(_cropTop * 100).toStringAsFixed(1)}%',
//                             style: TextStyle(
//                               color: Theme.of(context).colorScheme.primary,
//                               fontSize: 14,
//                               fontWeight: FontWeight.w600,
//                             ),
//                           ),
//                         ],
//                       ),
//                       Slider(
//                         value: _cropTop,
//                         min: 0.0,
//                         max: 0.5,
//                         divisions: 50,
//                         activeColor: Theme.of(context).colorScheme.primary,
//                         inactiveColor: Colors.white.withValues(alpha: 0.2),
//                         onChanged: (value) {
//                           if (value < _cropBottom) {
//                             setState(() {
//                               _cropTop = value;
//                             });
//                             _generateCroppedPreview();
//                           }
//                         },
//                       ),
//                     ],
//                   ),
//
//                   const SizedBox(height: 20),
//
//                   // Bottom Crop Slider
//                   Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           const Text(
//                             'Bottom Crop',
//                             style: TextStyle(color: Colors.white, fontSize: 14),
//                           ),
//                           Text(
//                             '${(_cropBottom * 100).toStringAsFixed(1)}%',
//                             style: TextStyle(
//                               color: Theme.of(context).colorScheme.primary,
//                               fontSize: 14,
//                               fontWeight: FontWeight.w600,
//                             ),
//                           ),
//                         ],
//                       ),
//                       Slider(
//                         value: _cropBottom,
//                         min: 0.1,
//                         max: 1.0,
//                         divisions: 90,
//                         activeColor: Theme.of(context).colorScheme.primary,
//                         inactiveColor: Colors.white.withValues(alpha: 0.2),
//                         onChanged: (value) {
//                           if (value > _cropTop) {
//                             setState(() {
//                               _cropBottom = value;
//                             });
//                             _generateCroppedPreview();
//                           }
//                         },
//                       ),
//                     ],
//                   ),
//
//                   const SizedBox(height: 16),
//
//                   // Crop Preview
//                   if (_selectedImage != null) ...[
//                     Container(
//                       width: double.infinity,
//                       height: 200,
//                       decoration: BoxDecoration(
//                         borderRadius: BorderRadius.circular(12),
//                         border: Border.all(
//                           color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
//                         ),
//                       ),
//                       child: ClipRRect(
//                         borderRadius: BorderRadius.circular(12),
//                         child: _croppedPreviewImage != null
//                             ? Image.file(
//                                 _croppedPreviewImage!,
//                                 fit: BoxFit.contain,
//                                 width: double.infinity,
//                                 height: double.infinity,
//                               )
//                             : Container(
//                                 color: Colors.black.withValues(alpha: 0.3),
//                                 child: const Center(
//                                   child: Column(
//                                     mainAxisAlignment: MainAxisAlignment.center,
//                                     children: [
//                                       Icon(
//                                         Icons.crop_free,
//                                         color: Colors.grey,
//                                         size: 32,
//                                       ),
//                                       SizedBox(height: 8),
//                                       Text(
//                                         'Generating preview...',
//                                         style: TextStyle(
//                                           color: Colors.grey,
//                                           fontSize: 14,
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                 ),
//                               ),
//                       ),
//                     ),
//                     const SizedBox(height: 8),
//                     Center(
//                       child: Text(
//                         'Preview: ${((_cropBottom - _cropTop) * 100).toStringAsFixed(1)}% of image height',
//                         style: TextStyle(
//                           color: Colors.white.withValues(alpha: 0.7),
//                           fontSize: 12,
//                         ),
//                       ),
//                     ),
//                   ],
//
//                   const SizedBox(height: 16),
//
//                   // Action Buttons
//                   Row(
//                     children: [
//                       Expanded(
//                         child: OutlinedButton.icon(
//                           onPressed: _resetToDefaults,
//                           icon: const Icon(Icons.restore, size: 18),
//                           label: const Text('Reset to Defaults'),
//                           style: OutlinedButton.styleFrom(
//                             foregroundColor: Colors.white,
//                             side: BorderSide(
//                               color: Colors.white.withValues(alpha: 0.3),
//                             ),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(width: 12),
//                       Expanded(
//                         child: ElevatedButton.icon(
//                           onPressed: _isLoading ? null : _saveCropSettings,
//                           icon: _isLoading
//                               ? const SizedBox(
//                                   width: 16,
//                                   height: 16,
//                                   child: CircularProgressIndicator(
//                                     strokeWidth: 2,
//                                     valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
//                                   ),
//                                 )
//                               : const Icon(Icons.save, size: 18),
//                           label: Text(_isLoading ? 'Saving...' : 'Save Settings'),
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: Theme.of(context).colorScheme.primary,
//                             foregroundColor: Colors.black,
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//
//             const SizedBox(height: 24),
//
//             // Instructions Section
//             Container(
//               padding: const EdgeInsets.all(20),
//               decoration: BoxDecoration(
//                 color: Colors.blue.withValues(alpha: 0.1),
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(
//                   color: Colors.blue.withValues(alpha: 0.3),
//                 ),
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Row(
//                     children: [
//                       const Icon(
//                         Icons.info_outline,
//                         color: Colors.blue,
//                         size: 20,
//                       ),
//                       const SizedBox(width: 8),
//                       const Text(
//                         'Instructions',
//                         style: TextStyle(
//                           color: Colors.white,
//                           fontSize: 16,
//                           fontWeight: FontWeight.w600,
//                         ),
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 12),
//                   const Text(
//                     '1. Select a PhonePe transaction screenshot from your gallery\n'
//                     '2. Adjust the top and bottom crop sliders to select the horizontal strip containing the payee name and amount\n'
//                     '3. The crop area should include only the transaction details, not the header or footer\n'
//                     '4. Save your settings to use them for future OCR processing',
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 14,
//                       height: 1.5,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//
//             const SizedBox(height: 24),
//
//             // Current Settings Display
//             if (_isCalibrated) ...[
//               Container(
//                 padding: const EdgeInsets.all(20),
//                 decoration: BoxDecoration(
//                   color: Colors.green.withValues(alpha: 0.1),
//                   borderRadius: BorderRadius.circular(16),
//                   border: Border.all(
//                     color: Colors.green.withValues(alpha: 0.3),
//                   ),
//                 ),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Row(
//                       children: [
//                         const Icon(
//                           Icons.check_circle,
//                           color: Colors.green,
//                           size: 20,
//                         ),
//                         const SizedBox(width: 8),
//                         const Text(
//                           'Current Settings',
//                           style: TextStyle(
//                             color: Colors.white,
//                             fontSize: 16,
//                             fontWeight: FontWeight.w600,
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 12),
//                     Text(
//                       'Top: ${(_cropTop * 100).toStringAsFixed(1)}%\n'
//                       'Bottom: ${(_cropBottom * 100).toStringAsFixed(1)}%\n'
//                       'Height: ${((_cropBottom - _cropTop) * 100).toStringAsFixed(1)}%',
//                       style: const TextStyle(
//                         color: Colors.white,
//                         fontSize: 14,
//                         height: 1.5,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ],
//         ),
//       ),
//     );
//   }
// }
