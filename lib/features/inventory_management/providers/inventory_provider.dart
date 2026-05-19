import 'package:flutter/foundation.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import '../services/inventory_service.dart';
import '../../inventory_selection/providers/inventory_list_provider.dart';

class InventoryProvider extends ChangeNotifier {
  InventoryProvider(this._service, this._listProvider);

  final InventoryListProvider _listProvider;
  final InventoryService _service;

  String? get currentInventoryId => _listProvider.selectedInventoryId;

  String? get currentInventoryName =>
      _listProvider.getSelectedInventoryName();

  List<String> get labels => _service.labels;

  bool get hasLabels => _service.hasLabels;

  InventorySettings? get currentSettings => _service.currentSettings;

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

  Future<void> createLabel(String label) async {
    await _service.createLabel(label);
    notifyListeners();
  }

  Future<void> renameLabel(
      String oldLabel, String newLabel) async {
    await _service.renameLabel(oldLabel, newLabel);
    notifyListeners();
  }

  Future<void> deleteLabel(String label) async {
    await _service.deleteLabel(label);
    notifyListeners();
  }

  bool hasLabel(String label) => _service.hasLabel(label);

  List<InventoryItem> getItems(String label) =>
      _service.getItemsByLabel(label);

  Future<void> saveItem(InventoryItem item) async {
    if (_listProvider.selectedInventoryId == null) return;
    await _service.saveItem(item);
    notifyListeners();
  }

  Map<String, List<InventoryItem>> getAllItems() =>
      _service.getAllItems();

  List<Map<String, dynamic>> searchAllInventories(String query) {
    return _service.searchAllInventories(query);
  }

  Future<void> updateSettings(InventorySettings settings) async {
    await _service.updateSettings(settings);
    notifyListeners();
  }
}