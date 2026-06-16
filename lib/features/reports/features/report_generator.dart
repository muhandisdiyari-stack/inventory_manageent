import '../../inventory_management/models/inventory_item.dart';
import '../../inventory_management/models/inventory_settings.dart';
import '../services/csv_service.dart';
import 'report_utils.dart';

class ReportResult {
  final String csvData;
  final String fileName;
  final String? filePath;
  final int totalItems;

  ReportResult({
    required this.csvData,
    required this.fileName,
    this.filePath,
    required this.totalItems,
  });
}

class ReportGenerator {
  final CsvService csvService;

  ReportGenerator({required this.csvService});

  Future<ReportResult> generateReport({
    required List<InventoryItem> allItems,
    required InventorySettings? settings,
    required String reportType,
    required Set<String> selectedFields,
    required String inventoryName,
    required Function(double progress, String message) onProgress,
  }) async {
    final filteredItems =
        ReportUtils.getFilteredItems(allItems, reportType);

    if (filteredItems.isEmpty) {
      throw Exception('No items found for selected filter');
    }

    final selectedFieldsList = List<String>.from(selectedFields);
    if (!selectedFieldsList.contains('Inventory')) {
      selectedFieldsList.add('Inventory');
    }

    final totalItems = filteredItems.length;

    onProgress(0.1, 'Processing $totalItems items...');
    await Future.delayed(const Duration(milliseconds: 50));

    // FIXED: Don't use compute() — Hive objects can't be sent across isolates.
    // Generate CSV directly on the main thread. For large datasets this is fine
    // because CsvService operations are fast (pure string manipulation).
    final csvString = csvService.generateCsvWithFields(
      filteredItems,
      settings,
      inventoryName,
      reportType == 'all'
          ? 'All Items'
          : reportType == 'expiring'
              ? 'Expiring Soon'
              : 'Expired',
      selectedFieldsList,
    );

    onProgress(0.8, 'Saving file...');
    await Future.delayed(const Duration(milliseconds: 50));

    final timestamp = DateTime.now();
    final safeName = ReportUtils.sanitizeFileName(inventoryName);
    final fileName =
        '${safeName}_report_${ReportUtils.formatTimestamp(timestamp)}.csv';

    final savedPath = await csvService.saveFile(csvString, fileName);

    onProgress(1.0, savedPath != null ? 'Complete!' : 'Saved locally');
    await Future.delayed(const Duration(milliseconds: 300));

    return ReportResult(
      csvData: csvString,
      fileName: fileName,
      filePath: savedPath,
      totalItems: totalItems,
    );
  }
}