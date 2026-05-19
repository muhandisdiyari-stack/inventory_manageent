import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    final results = <Permission, PermissionStatus>{};

    try {
      results[Permission.camera] = await Permission.camera.request();
    } catch (_) {}

    if (!kIsWeb) {
      try {
        results[Permission.storage] = await Permission.storage.request();
      } catch (_) {}
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        results[Permission.manageExternalStorage] =
            await Permission.manageExternalStorage.request();
      } catch (_) {}
    }

    return results;
  }

  static Future<bool> hasCameraPermission() async {
    if (kIsWeb) return true;
    try {
      return await Permission.camera.isGranted;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> hasStoragePermission() async {
    if (kIsWeb) return true;
    try {
      return await Permission.storage.isGranted ||
          await Permission.manageExternalStorage.isGranted;
    } catch (_) {
      return true;
    }
  }
}