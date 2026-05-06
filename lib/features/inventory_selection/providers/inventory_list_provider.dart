import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_list_item.dart';
import '../../inventory_management/services/inventory_service.dart';

class InventoryListProvider extends ChangeNotifier {
  final Box _inventoriesListBox;
  
  List<InventoryListItem> _inventories = [];
  String? _selectedInventoryId;
  bool _isInitialized = false;

  InventoryListProvider() : _inventoriesListBox = Hive.box('inventories_list') {
    debugPrint('Provider created');
  }

  List<InventoryListItem> get inventories => List.unmodifiable(_inventories);
  String? get selectedInventoryId => _selectedInventoryId;
  bool get hasInventories => _inventories.isNotEmpty;
  bool get isInitialized => _isInitialized;

  /// Initialize and load inventories - call this after widget is built
  void initialize() {
    if (!_isInitialized) {
      debugPrint('Initializing provider');
      _loadInventories();
      _isInitialized = true;
      notifyListeners();
      debugPrint('After init - inventories count: ${_inventories.length}');
    }
  }

  void _loadInventories() {
    debugPrint('Loading inventories from Hive');
    _inventories = [];
    for (var key in _inventoriesListBox.keys) {
      final value = _inventoriesListBox.get(key);
      debugPrint('Hive key: $key, value: $value');
      if (value is Map) {
        final Map<String, dynamic> typedMap = {};
        value.forEach((k, v) {
          typedMap[k.toString()] = v;
        });
        final name = typedMap['name'] as String? ?? '';
        if (name.isNotEmpty) {
          _inventories.add(InventoryListItem.fromMap(key, typedMap));
          debugPrint('Added inventory: $name');
        }
      }
    }
    debugPrint('Total inventories loaded: ${_inventories.length}');
  }

  /// Public method to refresh inventories (for pull-to-refresh)
  Future<void> refreshInventories() async {
    debugPrint('Refreshing inventories');
    _loadInventories();
    notifyListeners();
  }

  Future<String> createInventory(String name, InventoryService service) async {
    debugPrint('Creating inventory: $name');
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await _inventoriesListBox.put(id, {
      'name': name,
      'created': DateTime.now().toIso8601String(),
    });
    
    await service.initializeForInventory(id);
    
    _selectedInventoryId ??= id;
    
    _loadInventories();
    notifyListeners();
    debugPrint('Created inventory with id: $id');
    return id;
  }

  Future<void> renameInventory(String id, String newName) async {
    debugPrint('Renaming inventory $id to $newName');
    final data = _inventoriesListBox.get(id);
    if (data is Map) {
      data['name'] = newName;
      await _inventoriesListBox.put(id, data);
      _loadInventories();
      notifyListeners();
    }
  }

  Future<void> deleteInventory(String id, InventoryService service) async {
    debugPrint('Deleting inventory: $id');
    debugPrint('Before delete - Hive contains key $id: ${_inventoriesListBox.containsKey(id)}');
    
    await _inventoriesListBox.delete(id);
    await service.deleteInventoryData(id);
    
    debugPrint('After Hive delete - contains key $id: ${_inventoriesListBox.containsKey(id)}');
    
    if (_selectedInventoryId == id) {
      _selectedInventoryId = _inventories
          .where((inv) => inv.id != id)
          .toList()
          .isNotEmpty
          ? _inventories.firstWhere((inv) => inv.id != id).id
          : null;
    }
    
    _loadInventories();
    notifyListeners();
    debugPrint('After delete - inventories count: ${_inventories.length}');
  }

  void selectInventory(String id) {
    debugPrint('Selecting inventory: $id');
    _selectedInventoryId = id;
    notifyListeners();
  }

  String? getSelectedInventoryName() {
    if (_selectedInventoryId == null) return null;
    final data = _inventoriesListBox.get(_selectedInventoryId);
    if (data is Map) {
      return data['name'] as String?;
    }
    return null;
  }
}