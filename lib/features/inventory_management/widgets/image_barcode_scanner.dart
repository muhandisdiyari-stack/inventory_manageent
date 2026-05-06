
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class ImageBarcodeScanner {
  static Future<void> pickAndScan(
    BuildContext context, {
    required Function(String) onBarcodeScanned,
  }) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      
      if (pickedFile == null) return;
      
      if (context.mounted) {
        _showScanningDialog(context);
      }
      
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final barcodeScanner = BarcodeScanner(formats: [
        BarcodeFormat.all,
      ]);
      
      final barcodes = await barcodeScanner.processImage(inputImage);
      
      if (context.mounted) {
        Navigator.pop(context); // Close scanning dialog
      }
      
      if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
        onBarcodeScanned(barcodes.first.rawValue!);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No barcode found in image'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
      
      barcodeScanner.close();
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close scanning dialog if open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning barcode: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  static void _showScanningDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Scanning barcode...'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}