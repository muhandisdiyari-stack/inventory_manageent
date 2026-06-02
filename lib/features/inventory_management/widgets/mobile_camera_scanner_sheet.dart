import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class MobileCameraScannerSheet {
  static Future<void> show(BuildContext context, {required Function(String) onBarcodeScanned}) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Camera scanning is not supported on this platform. Use USB scanner or scan from image instead.'),
        ));
      }
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No camera available'))); }
        return;
      }
      if (context.mounted) {
        showDialog(
          context: context, barrierDismissible: false,
          builder: (_) => _MobileCameraScannerDialog(
            cameras: cameras,
            onBarcodeScanned: (barcode) { Navigator.pop(context); onBarcodeScanned(barcode); },
          ),
        );
      }
    } catch (e) {
      if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera error: $e'))); }
    }
  }
}

class _MobileCameraScannerDialog extends StatefulWidget {
  final List<CameraDescription> cameras;
  final Function(String) onBarcodeScanned;
  const _MobileCameraScannerDialog({required this.cameras, required this.onBarcodeScanned});

  @override
  State<_MobileCameraScannerDialog> createState() => _MobileCameraScannerDialogState();
}

class _MobileCameraScannerDialogState extends State<_MobileCameraScannerDialog> {
  CameraController? _controller;
  CameraDescription? _selectedCamera;
  bool _isInitialized = false;
  bool _isScanning = true;
  String? _lastScanned;
  bool _isDisposed = false;
  final BarcodeScanner _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]);
  DateTime _lastScanTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedCamera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back, orElse: () => widget.cameras.first,
    );
    _initializeCamera();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller?.dispose();
    _controller = null;
    _barcodeScanner.close();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    if (_selectedCamera == null) return;
    _controller = CameraController(_selectedCamera!, ResolutionPreset.medium, enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888);
    await _controller!.initialize();
    if (!mounted || _isDisposed) return;
    setState(() => _isInitialized = true);
    _startBarcodeScanning();
  }

  void _startBarcodeScanning() {
    _controller?.startImageStream((image) {
      if (!_isScanning || _isDisposed) return;
      final now = DateTime.now();
      if (now.difference(_lastScanTime).inMilliseconds < 300) return;
      _lastScanTime = now;
      _scanBarcode(image);
    });
  }

  Future<void> _scanBarcode(CameraImage image) async {
    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return;
      final barcodes = await _barcodeScanner.processImage(inputImage);
      if (!mounted || _isDisposed) return;
      for (final barcode in barcodes) {
        if (barcode.rawValue != null && barcode.rawValue != _lastScanned && _isScanning) {
          _lastScanned = barcode.rawValue; _isScanning = false;
          widget.onBarcodeScanned(barcode.rawValue!); return;
        }
      }
    } catch (_) {}
  }

  InputImage? _convertCameraImage(CameraImage image) {
    final rotation = _getImageRotation();
    final format = Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(size: Size(image.width.toDouble(), image.height.toDouble()), rotation: rotation, format: format, bytesPerRow: plane.bytesPerRow),
    );
  }

  InputImageRotation _getImageRotation() {
    final rotation = _selectedCamera?.sensorOrientation ?? 0;
    switch (rotation) {
      case 90: return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default: return InputImageRotation.rotation0deg;
    }
  }

  void _handleDismiss() {
    _isDisposed = true;
    _controller?.dispose();
    _controller = null;
    _barcodeScanner.close();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) { if (didPop) _handleDismiss(); },
      child: Dialog(
        backgroundColor: Colors.black,
        child: SizedBox(
          width: 640, height: 480,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(12), color: Colors.grey[900],
              child: Row(children: [
                const Icon(Icons.qr_code_scanner, color: Colors.white, size: 20), const SizedBox(width: 8),
                const Text('Scan Barcode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (_lastScanned != null) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
                  child: Text(_lastScanned!, style: const TextStyle(color: Colors.green, fontSize: 12)),
                ),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () { _handleDismiss(); Navigator.pop(context); }),
              ]),
            ),
            Expanded(
              child: _isInitialized
                  ? Stack(children: [
                      CameraPreview(_controller!),
                      Center(child: Container(width: 300, height: 200, decoration: BoxDecoration(
                        border: Border.all(color: _isScanning ? Colors.green : Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ))),
                    ])
                  : const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(), SizedBox(height: 16),
                      Text('Initializing camera...', style: TextStyle(color: Colors.white)),
                    ])),
            ),
            Container(
              padding: const EdgeInsets.all(12), color: Colors.grey[900],
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Position barcode in the green frame', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}