import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

enum BarcodeScannerType {
  camera,
  keyboard,
  image,
  unsupported,
}

class BarcodeScannerService {
  /// Detects the best available barcode scanning method for the platform
  static BarcodeScannerType get bestAvailableType {
    // ⚠️ Check kIsWeb FIRST — Platform.* throws on web
    if (kIsWeb) {
      return BarcodeScannerType.keyboard;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return BarcodeScannerType.camera;
    } else if (Platform.isWindows || Platform.isLinux) {
      return BarcodeScannerType.keyboard;
    } else if (Platform.isMacOS) {
      return BarcodeScannerType.camera;
    }
    return BarcodeScannerType.unsupported;
  }

  /// Returns list of all supported scanning methods for the platform
  static List<BarcodeScannerType> get supportedTypes {
    // ⚠️ Check kIsWeb FIRST
    if (kIsWeb) {
      return [
        BarcodeScannerType.keyboard,
        BarcodeScannerType.image,
      ];
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return [
        BarcodeScannerType.camera,
        BarcodeScannerType.image,
        BarcodeScannerType.keyboard,
      ];
    } else if (Platform.isWindows || Platform.isLinux) {
      return [
        BarcodeScannerType.keyboard,
        BarcodeScannerType.image,
        BarcodeScannerType.camera,
      ];
    } else if (Platform.isMacOS) {
      return [
        BarcodeScannerType.camera,
        BarcodeScannerType.image,
        BarcodeScannerType.keyboard,
      ];
    }
    return [BarcodeScannerType.keyboard];
  }

  /// Whether camera-based scanning is available
  static bool get hasCameraSupport {
    if (kIsWeb) return false;
    return Platform.isAndroid ||
           Platform.isIOS ||
           Platform.isMacOS ||
           (Platform.isWindows && _hasWebcam()) ||
           (Platform.isLinux && _hasWebcam());
  }

  /// Simple check for webcam availability (platform-specific)
  static bool _hasWebcam() {
    // In a real app, you'd check for camera availability
    // For now, assume camera might be available on desktop
    return true;
  }
}