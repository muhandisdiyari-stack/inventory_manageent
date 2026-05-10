import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_list_item.dart';
import '../../inventory_management/services/inventory_service.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';

class InventoryListProvider extends ChangeNotifier {
  final Box _inventoriesListBox;
  
  List<InventoryListItem> _inventories = [];
  String? _selectedInventoryId;
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;

  InventoryListProvider() : _inventoriesListBox = Hive.box('inventories_list');

  List<InventoryListItem> get inventories => List.unmodifiable(_inventories);
  String? get selectedInventoryId => _selectedInventoryId;
  bool get hasInventories => _inventories.isNotEmpty;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void initialize() {
    if (!_isInitialized) {
      _loadInventories();
      _isInitialized = true;
      notifyListeners();
    }
  }

  void _loadInventories() {
    _inventories = [];
    for (var key in _inventoriesListBox.keys) {
      final value = _inventoriesListBox.get(key);
      if (value is Map) {
        final Map<String, dynamic> typedMap = {};
        value.forEach((k, v) {
          typedMap[k.toString()] = v;
        });
        final name = typedMap['name'] as String? ?? '';
        if (name.isNotEmpty) {
          _inventories.add(InventoryListItem.fromMap(key, typedMap));
        }
      }
    }
    _inventories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> refreshInventories() async {
    _isLoading = true;
    notifyListeners();
    
    _loadInventories();
    _isLoading = false;
    notifyListeners();
  }

  Future<String> createInventory(String name, InventoryService service) async {
    if (name.trim().isEmpty) throw Exception('Inventory name cannot be empty');

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = '${now}_${name.hashCode.abs()}';
      
      final timestamp = DateTime.now();
      await _inventoriesListBox.put(id, {
        'name': name.trim(),
        'created': timestamp.toIso8601String(),
        'modified': timestamp.toIso8601String(),
      });
      
      await service.initializeForInventory(id);
      _selectedInventoryId ??= id;
      
      _loadInventories();
      _isLoading = false;
      notifyListeners();
      
      // Log activity
      final logEntry = ActivityLogEntry(
        id: timestamp.microsecondsSinceEpoch.toString(),
        timestamp: timestamp,
        action: 'created',
        entityType: 'inventory',
        entityName: name.trim(),
        inventoryId: id,
        inventoryName: name.trim(),
        details: 'Inventory created: "${name.trim()}"',
      );
      await ActivityLogService().addLog(logEntry);
      
      return id;
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to create inventory: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> renameInventory(String id, String newName) async {
    if (newName.trim().isEmpty) throw Exception('Inventory name cannot be empty');

    try {
      final data = _inventoriesListBox.get(id);
      if (data is Map) {
        final oldName = data['name'] as String? ?? '';
        final updatedData = Map<String, dynamic>.from(data);
        updatedData['name'] = newName.trim();
        updatedData['modified'] = DateTime.now().toIso8601String();
        await _inventoriesListBox.put(id, updatedData);
        _loadInventories();
        notifyListeners();
        
        // Log activity
        final logEntry = ActivityLogEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          action: 'modified',
          entityType: 'inventory',
          entityName: newName.trim(),
          inventoryId: id,
          inventoryName: newName.trim(),
          details: 'Inventory renamed',
          changes: {
            'name': FieldChange(oldValue: oldName, newValue: newName.trim()),
          },
        );
        await ActivityLogService().addLog(logEntry);
      }
    } catch (e) {
      debugPrint('Error renaming inventory: $e');
      _error = 'Failed to rename inventory: $e';
      notifyListeners();
    }
  }

  Future<void> deleteInventory(String id, InventoryService service) async {
    _error = null;

    try {
      final data = _inventoriesListBox.get(id);
      final inventoryName = data is Map ? (data['name'] as String? ?? '') : '';
      
      await _inventoriesListBox.delete(id);
      await service.deleteInventoryData(id);
      
      // Log activity BEFORE clearing logs for this inventory
      final logEntry = ActivityLogEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        action: 'deleted',
        entityType: 'inventory',
        entityName: inventoryName,
        inventoryId: id,
        inventoryName: inventoryName,
        details: 'Inventory deleted: "$inventoryName"',
      );
      await ActivityLogService().addLog(logEntry);
      
      _loadInventories();
      
      if (_selectedInventoryId == id) {
        _selectedInventoryId = _inventories.isNotEmpty ? _inventories.first.id : null;
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting inventory: $e');
      _error = 'Failed to delete inventory: $e';
      notifyListeners();
      rethrow;
    }
  }

  void selectInventory(String id) {
    if (_selectedInventoryId != id) {
      _selectedInventoryId = id;
      notifyListeners();
    }
  }

  String? getSelectedInventoryName() {
    if (_selectedInventoryId == null) return null;
    final data = _inventoriesListBox.get(_selectedInventoryId);
    if (data is Map) return data['name'] as String?;
    return null;
  }
}