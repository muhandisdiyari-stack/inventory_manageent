import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../../inventory_management/models/inventory_item.dart';
import '../../inventory_management/models/inventory_settings.dart';
import '../../../core/utils/file_export.dart';
import '../features/report_utils.dart';

// Native imports - these are only used inside kIsWeb guards
import 'dart:io' show File, Directory, Platform;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class CsvService {
  /// Returns headers based on settings AND user-selected fields.
  List<String> _getHeaders(
      InventorySettings? settings, List<String>? selectedFields) {
    if (selectedFields != null && selectedFields.isNotEmpty) {
      return List<String>.from(selectedFields);
    }

    final headers = <String>[];

    if (settings != null) {
      for (var field in settings.activeFields) {
        headers.add(field.fieldName);
      }
    } else {
      headers.addAll([
        'Name', 'Code', 'Barcode', 'Size', 'Quantity', 'Label', 'Note'
      ]);
    }

    if (!headers.contains('Quantity')) headers.add('Quantity');
    if (!headers.contains('Label')) headers.add('Label');

    if (settings != null) {
      for (var customField in settings.customFieldNames) {
        if (!headers.contains(customField)) {
          headers.add(customField);
        }
      }
    }

    return headers;
  }

  String generateCsv(
    List<InventoryItem> items,
    InventorySettings? settings,
    String inventoryName,
    String reportType,
  ) {
    return generateCsvWithFields(
        items, settings, inventoryName, reportType, null);
  }

  String generateCsvWithFields(
    List<InventoryItem> items,
    InventorySettings? settings,
    String inventoryName,
    String reportType,
    List<String>? selectedFields,
  ) {
    final headers = _getHeaders(settings, selectedFields);
    final rows = <List<dynamic>>[];

    rows.add(['# Inventory: $inventoryName']);
    rows.add(['# Generated: ${DateTime.now().toIso8601String()}']);
    rows.add(['# Report Type: $reportType']);
    rows.add(['# Total Items: ${items.length}']);
    rows.add(['# Fields: ${headers.join(', ')}']);
    rows.add(headers);

    for (var item in items) {
      final row = <dynamic>[];
      for (var header in headers) {
        row.add(ReportUtils.getFieldValue(item, header, inventoryName));
      }
      rows.add(row);
    }

    return const ListToCsvConverter().convert(rows);
  }

  /// Save CSV file with platform-appropriate handling.
  Future<String?> saveFile(String csvString, String fileName) async {
    try {
      final bytes = utf8.encode(csvString);

      if (kIsWeb) {
        downloadFileWeb(bytes, fileName, 'text/csv');
        return 'web_download';
      }

      return await _saveFileNative(bytes, fileName);
    } catch (e) {
      debugPrint('CsvService.saveFile error: $e');
      return null;
    }
  }

  /// Native file saving - only called on non-web platforms.
  Future<String?> _saveFileNative(List<int> bytes, String fileName) async {
    // Convert to Uint8List once for all native operations
    final uint8Bytes = Uint8List.fromList(bytes);

    try {
      if (Platform.isAndroid) {
        // Method 1: File picker (let user choose location)
        try {
          final result = await FilePicker.platform.saveFile(
            dialogTitle: 'Save CSV Report',
            fileName: fileName,
            type: FileType.custom,
            allowedExtensions: ['csv'],
            bytes: uint8Bytes,
          );

          if (result != null && result.isNotEmpty) {
            return result;
          }
        } catch (e) {
          debugPrint('FilePicker save failed: $e');
        }

        // Method 2: Save to Downloads
        try {
          final savedPath =
              await _saveToAndroidDownloads(uint8Bytes, fileName);
          if (savedPath != null) return savedPath;
        } catch (e) {
          debugPrint('Android Downloads save failed: $e');
        }

        // Method 3: App-specific external storage
        try {
          final dir = await getExternalStorageDirectory();
          if (dir != null) {
            final localPath = '${dir.path}/$fileName';
            await File(localPath).writeAsBytes(uint8Bytes);
            return localPath;
          }
        } catch (e) {
          debugPrint('External storage fallback failed: $e');
        }

        // Method 4: Documents directory
        try {
          final dir = await getApplicationDocumentsDirectory();
          final localPath = '${dir.path}/$fileName';
          await File(localPath).writeAsBytes(uint8Bytes);
          return localPath;
        } catch (e) {
          debugPrint('Documents directory fallback failed: $e');
        }
      }

      if (Platform.isIOS) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final localPath = '${dir.path}/$fileName';
          await File(localPath).writeAsBytes(uint8Bytes);
          return localPath;
        } catch (e) {
          debugPrint('iOS save failed: $e');
        }
      }

      if (Platform.isWindows) {
        try {
          final downloadsDir = Directory(
            '${Platform.environment['USERPROFILE']}\\Downloads',
          );
          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }
          final localPath = '${downloadsDir.path}\\$fileName';
          await File(localPath).writeAsBytes(uint8Bytes);
          return localPath;
        } catch (e) {
          debugPrint('Windows save failed: $e');
        }
      }

      if (Platform.isMacOS || Platform.isLinux) {
        try {
          final homeDir = Platform.environment['HOME'] ?? '/tmp';
          final downloadsDir = Directory('$homeDir/Downloads');
          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }
          final localPath = '${downloadsDir.path}/$fileName';
          await File(localPath).writeAsBytes(uint8Bytes);
          return localPath;
        } catch (e) {
          debugPrint('Desktop save failed: $e');
        }
      }

      // Universal fallback
      try {
        final dir = await getApplicationDocumentsDirectory();
        final localPath = '${dir.path}/$fileName';
        await File(localPath).writeAsBytes(uint8Bytes);
        return localPath;
      } catch (e) {
        debugPrint('Universal fallback failed: $e');
        return null;
      }
    } catch (e) {
      debugPrint('_saveFileNative error: $e');
      return null;
    }
  }

  /// Save file to Android Downloads directory.
  Future<String?> _saveToAndroidDownloads(
      Uint8List bytes, String fileName) async {
    try {
      final manageStorageStatus =
          await Permission.manageExternalStorage.status;
      final storageStatus = await Permission.storage.status;

      if (!manageStorageStatus.isGranted && !storageStatus.isGranted) {
        final requested = await Permission.storage.request();
        if (!requested.isGranted) {
          final manageRequested =
              await Permission.manageExternalStorage.request();
          if (!manageRequested.isGranted) {
            return null;
          }
        }
      }

      final possiblePaths = [
        '/storage/emulated/0/Download',
        '/sdcard/Download',
        '/storage/sdcard0/Download',
        '/storage/emulated/0/Downloads',
        '/sdcard/Downloads',
      ];

      for (final path in possiblePaths) {
        final dir = Directory(path);
        if (await dir.exists()) {
          try {
            final file = File('${dir.path}/$fileName');
            await file.writeAsBytes(bytes);

            if (await file.exists() && await file.length() > 0) {
              return file.path;
            }
          } catch (e) {
            continue;
          }
        }
      }
    } catch (e) {
      debugPrint('_saveToAndroidDownloads error: $e');
    }
    return null;
  }

  /// Opens a file picker to select a CSV file and returns its contents.
  Future<String?> pickCsvFileContents() async {
    try {
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv'],
        );
        if (result != null && result.files.single.bytes != null) {
          return utf8.decode(result.files.single.bytes!);
        }
        return null;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      throw Exception('Failed to pick file: $e');
    }
  }

  /// Previews a CSV import by analysing the header row.
  ImportPreview previewImport(String csvData) {
    try {
      final rows = const CsvToListConverter().convert(csvData);
      if (rows.isEmpty) {
        return ImportPreview(
            hasRequiredColumns: false,
            labels: 0,
            items: 0,
            skipped: 0);
      }

      final dataRows = rows.where((row) {
        if (row.isEmpty) return false;
        final firstCell = row[0].toString();
        return !firstCell.startsWith('#');
      }).toList();

      if (dataRows.isEmpty) {
        return ImportPreview(
            hasRequiredColumns: false,
            labels: 0,
            items: 0,
            skipped: 0);
      }

      final headers =
          dataRows[0].map((h) => h.toString().toLowerCase()).toList();
      final hasLabel = headers.contains('label');
      final hasName = headers.contains('name');

      return ImportPreview(
        hasRequiredColumns: hasLabel || hasName,
        labels: dataRows.length - 1,
        items: dataRows.length - 1,
        skipped: 0,
      );
    } catch (e) {
      return ImportPreview(
          hasRequiredColumns: false,
          labels: 0,
          items: 0,
          skipped: 0);
    }
  }

  /// Imports items from CSV data, grouping them by label.
  Future<List<MapEntry<String, List<InventoryItem>>>> importFromCsv(
      String csvData) async {
    final rows = const CsvToListConverter().convert(csvData);
    if (rows.isEmpty) return [];

    final dataRows = rows.where((row) {
      if (row.isEmpty) return false;
      final firstCell = row[0].toString();
      return !firstCell.startsWith('#');
    }).toList();

    if (dataRows.isEmpty) return [];

    final headers = dataRows[0].map((h) => h.toString()).toList();
    final dataRowsWithoutHeader = dataRows.sublist(1);

    final itemsByLabel = <String, List<InventoryItem>>{};

    for (var row in dataRowsWithoutHeader) {
      if (row.isEmpty) continue;

      final item = InventoryItem();

      for (int i = 0; i < headers.length && i < row.length; i++) {
        final header = headers[i].toString();
        final value = row[i].toString();

        switch (header.toLowerCase()) {
          case 'name':
            item.name = value;
            break;
          case 'code':
            item.code = value;
            break;
          case 'barcode':
            item.barcode = value;
            break;
          case 'color':
            item.color = value;
            break;
          case 'material':
            item.material = value;
            break;
          case 'size':
            item.size = value;
            break;
          case 'production date':
            try {
              item.productionDate = DateTime.parse(value);
            } catch (_) {}
            break;
          case 'expire date':
            try {
              item.expireDate = DateTime.parse(value);
            } catch (_) {}
            break;
          case 'note':
            item.note = value;
            break;
          case 'quantity':
            item.quantity = int.tryParse(value) ?? 0;
            break;
          case 'label':
            item.label = value;
            break;
          default:
            if (value.isNotEmpty) {
              item.customFields[header] = value;
            }
            break;
        }
      }

      final label = item.label.isNotEmpty ? item.label : 'Imported';
      itemsByLabel.putIfAbsent(label, () => []).add(item);
    }

    return itemsByLabel.entries.toList();
  }
}

class ImportPreview {
  final bool hasRequiredColumns;
  final int labels;
  final int items;
  final int skipped;

  ImportPreview({
    required this.hasRequiredColumns,
    required this.labels,
    required this.items,
    required this.skipped,
  });
}