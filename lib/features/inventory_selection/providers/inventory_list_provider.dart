import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_list_item.dart';
import '../../inventory_management/services/inventory_service.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

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
        final typedMap = <String, dynamic>{};
        value.forEach((k, v) => typedMap[k.toString()] = v);
        final name = typedMap['name'] as String? ?? '';
        if (name.isNotEmpty) {
          _inventories.add(InventoryListItem.fromMap(key.toString(), typedMap));
        }
      }
    }
    _inventories.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> refreshInventories() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _loadInventories();
    } catch (e) {
      _error = 'Failed to refresh: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String> createInventory(String name, InventoryService service) async {
    if (name.trim().isEmpty) throw Exception('Inventory name cannot be empty');
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final id = _uuid.v4();
      final timestamp = DateTime.now();

      await _inventoriesListBox.put(id, {
        'name': name.trim(),
        'created': timestamp.toIso8601String(),
        'modified': timestamp.toIso8601String(),
      });

      await service.initializeForInventory(id);
      _selectedInventoryId = id;
      _loadInventories();

      await ActivityLogService().addLog(ActivityLogEntry(
        id: _uuid.v4(),
        timestamp: timestamp,
        action: 'created',
        entityType: 'inventory',
        entityName: name.trim(),
        inventoryId: id,
        inventoryName: name.trim(),
        details: 'Inventory created: "${name.trim()}"',
      ));

      return id;
    } catch (e) {
      _error = 'Failed to create inventory: $e';
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> renameInventory(String id, String newName) async {
    if (newName.trim().isEmpty) throw Exception('Inventory name cannot be empty');
    try {
      final data = _inventoriesListBox.get(id);
      if (data is Map) {
        final typedMap = <String, dynamic>{};
        data.forEach((k, v) => typedMap[k.toString()] = v);
        final oldName = typedMap['name'] as String? ?? '';
        typedMap['name'] = newName.trim();
        typedMap['modified'] = DateTime.now().toIso8601String();
        await _inventoriesListBox.put(id, typedMap);
        _loadInventories();
        notifyListeners();

        await ActivityLogService().addLog(ActivityLogEntry(
          id: _uuid.v4(),
          timestamp: DateTime.now(),
          action: 'modified',
          entityType: 'inventory',
          entityName: newName.trim(),
          inventoryId: id,
          inventoryName: newName.trim(),
          details: 'Inventory renamed',
          changes: {'name': FieldChange(oldValue: oldName, newValue: newName.trim())},
        ));
      }
    } catch (e) {
      _error = 'Failed to rename: $e';
      notifyListeners();
    }
  }

  Future<void> deleteInventory(String id, InventoryService service) async {
    try {
      final data = _inventoriesListBox.get(id);
      final inventoryName = data is Map ? (data['name'] as String? ?? '') : '';

      await ActivityLogService().addLog(ActivityLogEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        action: 'deleted',
        entityType: 'inventory',
        entityName: inventoryName,
        inventoryId: id,
        inventoryName: inventoryName,
        details: 'Inventory deleted: "$inventoryName"',
      ));

      await ActivityLogService().clearLogs(inventoryId: id);
      await service.deleteInventoryData(id);
      await _inventoriesListBox.delete(id);
      _loadInventories();

      if (_selectedInventoryId == id) {
        _selectedInventoryId = _inventories.isNotEmpty ? _inventories.first.id : null;
      }
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete: $e';
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
    if (data is Map) {
      final typedMap = <String, dynamic>{};
      data.forEach((k, v) => typedMap[k.toString()] = v);
      return typedMap['name'] as String?;
    }
    return null;
  }
}