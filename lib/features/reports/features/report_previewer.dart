import '../../../core/constants/app_constants.dart';
import '../../inventory_management/models/inventory_item.dart';
import 'report_utils.dart';

class PreviewResult {
  final List<List<dynamic>>? data;
  final int totalItems;
  final String? error;
  final String? message;

  PreviewResult({
    this.data,
    required this.totalItems,
    this.error,
    this.message,
  });
}

class ReportPreviewer {
  PreviewResult preview({
    required List<InventoryItem> allItems,
    required String reportType,
    required Set<String> selectedFields,
    required String inventoryName,
  }) {
    final filteredItems =
        ReportUtils.getFilteredItems(allItems, reportType);

    if (filteredItems.isEmpty) {
      return PreviewResult(
        data: null,
        totalItems: 0,
        error: 'No items found for selected filter',
      );
    }

    final totalItems = filteredItems.length;
    final fieldsList = List<String>.from(selectedFields);
    if (!fieldsList.contains('Inventory')) {
      fieldsList.add('Inventory');
    }

    final previewItems = filteredItems.take(AppConstants.previewLimit);
    final dataRows = <List<dynamic>>[fieldsList];

    for (var item in previewItems) {
      final row = <dynamic>[];
      for (var field in fieldsList) {
        row.add(ReportUtils.getFieldValue(item, field, inventoryName));
      }
      dataRows.add(row);
    }

    String? message;
    if (filteredItems.length > AppConstants.previewLimit) {
      message =
          'Showing first ${AppConstants.previewLimit} of $totalItems items';
    }

    return PreviewResult(
      data: dataRows,
      totalItems: totalItems,
      message: message,
    );
  }
}