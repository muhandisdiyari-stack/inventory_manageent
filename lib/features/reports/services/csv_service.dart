import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../inventory_management/models/inventory_item.dart';
import '../../inventory_management/models/inventory_settings.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/file_export.dart'; // This imports downloadFileWeb function

class CsvService {
  /// Returns headers based on settings AND user-selected fields.
  List<String> _getHeaders(InventorySettings? settings, List<String>? selectedFields) {
    // If user explicitly selected fields, honour that selection
    if (selectedFields != null && selectedFields.isNotEmpty) {
      return List<String>.from(selectedFields);
    }

    final headers = <String>[];

    if (settings != null) {
      for (var field in settings.activeFields) {
        headers.add(field.fieldName);
      }
    } else {
      headers.addAll(['Name', 'Code', 'Barcode', 'Size', 'Quantity', 'Label', 'Note']);
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

  /// Standardised field-value resolver (mirrors the one in ReportsScreen).
  static dynamic getFieldValue(InventoryItem item, String fieldName, String inventoryName) {
    switch (fieldName) {
      case 'Name': return item.name;
      case 'Code': return item.code;
      case 'Barcode': return item.barcode;
      case 'Color': return item.color;
      case 'Material': return item.material;
      case 'Size': return item.size;
      case 'Production Date': return item.productionDate != null ? formatDateOnly(item.productionDate) : '';
      case 'Expire Date': return item.expireDate != null ? formatDateOnly(item.expireDate) : '';
      case 'Note': return item.note;
      case 'Quantity': return item.quantity.toString();
      case 'Label': return item.label;
      case 'Inventory': return inventoryName;
      default: return item.customFields[fieldName] ?? '';
    }
  }

  String generateCsv(
    List<InventoryItem> items,
    InventorySettings? settings,
    String inventoryName,
    String reportType,
  ) {
    return generateCsvWithFields(items, settings, inventoryName, reportType, null);
  }

  /// Generates CSV with the given [selectedFields].
  /// When [selectedFields] is null, falls back to active fields from settings.
  String generateCsvWithFields(
    List<InventoryItem> items,
    InventorySettings? settings,
    String inventoryName,
    String reportType,
    List<String>? selectedFields,
  ) {
    final headers = _getHeaders(settings, selectedFields);
    final rows = <List<dynamic>>[];

    // Minimal metadata as comments (prefixed with # so import can skip)
    rows.add(['# Inventory: $inventoryName']);
    rows.add(['# Generated: ${DateTime.now().toIso8601String()}']);
    rows.add(['# Report Type: $reportType']);
    rows.add(['# Total Items: ${items.length}']);
    rows.add(['# Fields: ${headers.join(', ')}']);
    rows.add(headers);

    for (var item in items) {
      final row = <dynamic>[];
      for (var header in headers) {
        row.add(getFieldValue(item, header, inventoryName));
      }
      rows.add(row);
    }

    return const ListToCsvConverter().convert(rows);
  }

  /// Save CSV file with platform-appropriate handling.
  ///
  /// - **Web**: Triggers a browser download via blob URL using downloadFileWeb()
  /// - **Native**: Tries file picker first, falls back to documents directory,
  ///   then falls back to temp directory
  ///
  /// Returns the file path on native platforms, or `'web_download'` on web.
  Future<String?> saveFile(String csvString, String fileName) async {
    try {
      // Encode to proper UTF-8 bytes (not UTF-16 code units)
      final bytes = utf8.encode(csvString);

      // ── Web platform: trigger browser download ─────────────────
      if (kIsWeb) {
        // Call the top-level function imported from file_export.dart
        downloadFileWeb(bytes, fileName, 'text/csv');
        return 'web_download';
      }

      // ── Native platforms ───────────────────────────────────────
      try {
        // Try file picker for user-selected location
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Save CSV Report',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['csv'],
          bytes: bytes,
        );

        if (result != null) {
          final savedFile = File(result);
          await savedFile.writeAsString(csvString);
          return result;
        }
      } catch (e) {
        // File picker failed or was cancelled - continue to local save
      }

      // ── Save to documents directory ───────────────────────────
      try {
        final directory = await getApplicationDocumentsDirectory();
        final localPath = '${directory.path}/$fileName';
        final localFile = File(localPath);
        await localFile.writeAsString(csvString);
        return localPath;
      } catch (e) {
        // Documents directory failed - continue to temp
      }

      // ── Last resort: temp directory ───────────────────────────
      try {
        final tempDir = Directory.systemTemp;
        final tempPath = '${tempDir.path}/$fileName';
        final tempFile = File(tempPath);
        await tempFile.writeAsString(csvString);
        return tempPath;
      } catch (e) {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Opens a file picker to select a CSV file and returns its contents.
  Future<String?> pickCsvFileContents() async {
    try {
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
        return ImportPreview(hasRequiredColumns: false, labels: 0, items: 0, skipped: 0);
      }

      // Skip comment lines (starting with #)
      final dataRows = rows.where((row) {
        if (row.isEmpty) return false;
        final firstCell = row[0].toString();
        return !firstCell.startsWith('#');
      }).toList();

      if (dataRows.isEmpty) {
        return ImportPreview(hasRequiredColumns: false, labels: 0, items: 0, skipped: 0);
      }

      final headers = dataRows[0].map((h) => h.toString().toLowerCase()).toList();
      final hasLabel = headers.contains('label');
      final hasName = headers.contains('name');

      return ImportPreview(
        hasRequiredColumns: hasLabel || hasName,
        labels: dataRows.length - 1,
        items: dataRows.length - 1,
        skipped: 0,
      );
    } catch (e) {
      return ImportPreview(hasRequiredColumns: false, labels: 0, items: 0, skipped: 0);
    }
  }

  /// Imports items from CSV data, grouping them by label.
  Future<List<MapEntry<String, List<InventoryItem>>>> importFromCsv(String csvData) async {
    final rows = const CsvToListConverter().convert(csvData);
    if (rows.isEmpty) return [];

    // Skip comment/metadata lines
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
          case 'name': item.name = value; break;
          case 'code': item.code = value; break;
          case 'barcode': item.barcode = value; break;
          case 'color': item.color = value; break;
          case 'material': item.material = value; break;
          case 'size': item.size = value; break;
          case 'production date':
            try { item.productionDate = DateTime.parse(value); } catch (_) {}
            break;
          case 'expire date':
            try { item.expireDate = DateTime.parse(value); } catch (_) {}
            break;
          case 'note': item.note = value; break;
          case 'quantity':
            item.quantity = int.tryParse(value) ?? 0;
            break;
          case 'label': item.label = value; break;
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