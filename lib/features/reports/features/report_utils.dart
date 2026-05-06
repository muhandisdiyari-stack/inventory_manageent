import '../../inventory_management/providers/inventory_provider.dart';
import '../../inventory_management/models/inventory_item.dart';
import '../../../core/utils/date_utils.dart';

class ReportUtils {
  static List<InventoryItem> getFilteredItems(InventoryProvider provider, String reportType) {
    final allItems = provider.getAllItems();
    final items = <InventoryItem>[];
    
    for (var entry in allItems.entries) {
      items.addAll(entry.value);
    }
    
    switch (reportType) {
      case 'expiring':
        return items.where((item) => item.isExpiringSoon).toList();
      case 'expired':
        return items.where((item) => item.isExpired).toList();
      default:
        return items;
    }
  }

  static dynamic getFieldValue(InventoryItem item, String fieldName, String inventoryName) {
    switch (fieldName) {
      case 'Name':
        return item.name;
      case 'Code':
        return item.code;
      case 'Barcode':
        return item.barcode;
      case 'Color':
        return item.color;
      case 'Material':
        return item.material;
      case 'Size':
        return item.size;
      case 'Production Date':
        return item.productionDate != null ? formatDateOnly(item.productionDate) : '';
      case 'Expire Date':
        return item.expireDate != null ? formatDateOnly(item.expireDate) : '';
      case 'Note':
        return item.note;
      case 'Quantity':
        return item.quantity.toString();
      case 'Label':
        return item.label;
      case 'Inventory':
        return inventoryName;
      default:
        return item.customFields[fieldName] ?? '';
    }
  }

  static String sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
  }

  static String formatTimestamp(DateTime timestamp) {
    return '${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}'
        '${timestamp.day.toString().padLeft(2, '0')}_'
        '${timestamp.hour.toString().padLeft(2, '0')}'
        '${timestamp.minute.toString().padLeft(2, '0')}';
  }
}