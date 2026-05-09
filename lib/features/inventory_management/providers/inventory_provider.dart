import 'package:flutter/foundation.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import '../services/inventory_service.dart';
import '../../inventory_selection/providers/inventory_list_provider.dart';

class InventoryProvider extends ChangeNotifier {
  final InventoryService _service;
  final InventoryListProvider _listProvider;

  InventoryProvider(this._service, this._listProvider);

  String? get currentInventoryId => _listProvider.selectedInventoryId;
  String? get currentInventoryName => _listProvider.getSelectedInventoryName();

  List<String> get labels => _service.labels;
  bool get hasLabels => _service.hasLabels;

  InventorySettings? get currentSettings => _service.currentSettings;

  /// Single source of truth for selected inventory is the ListProvider.
  /// Service derives from it.
  void selectInventory(String id) {
    _listProvider.selectInventory(id);
    _service.selectInventory(id);
    notifyListeners();
  }

  Future<void> initializeCurrentInventory() async {
    final id = _listProvider.selectedInventoryId;
    if (id != null) {
      await _service.initializeForInventory(id);
      notifyListeners();
    }
  }

  // Label operations
  Future<void> createLabel(String label) async {
    await _service.createLabel(label);
    notifyListeners();
  }

  Future<void> renameLabel(String oldLabel, String newLabel) async {
    await _service.renameLabel(oldLabel, newLabel);
    notifyListeners();
  }

  Future<void> deleteLabel(String label) async {
    await _service.deleteLabel(label);
    notifyListeners();
  }

  bool hasLabel(String label) => _service.hasLabel(label);

  // Item operations
  List<InventoryItem> getItems(String label) => _service.getItemsByLabel(label);

  /// FIX (bug): delegate entirely to the service which already manages box
  /// access. The previous implementation duplicated Hive.openBox logic here,
  /// risking type conflicts and bypassing the service's internal state.
  Future<void> saveItem(InventoryItem item) async {
    if (_listProvider.selectedInventoryId == null) return;
    await _service.saveItem(item);
    notifyListeners();
  }

  Map<String, List<InventoryItem>> getAllItems() => _service.getAllItems();

  // Cross-inventory search with inventory names
  List<Map<String, dynamic>> searchAllInventories(String query) {
    return _service.searchAllInventories(query);
  }

  // Settings
  Future<void> updateSettings(InventorySettings settings) async {
    await _service.updateSettings(settings);
    notifyListeners();
  }
}