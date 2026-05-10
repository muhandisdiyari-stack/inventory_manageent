import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';

class InventoryService {
  final Map<String, Box<InventoryItem>> _itemsBoxes = {};
  final Map<String, Box> _labelsBoxes = {};
  final Map<String, Box<InventorySettings>> _settingsBoxes = {};

  String? _currentInventoryId;

  String? get currentInventoryId => _currentInventoryId;

  Future<void> initializeForInventory(String inventoryId) async {
    final String labelsBoxName = 'labels_$inventoryId';
    Box labelsBox;
    if (Hive.isBoxOpen(labelsBoxName)) {
      labelsBox = Hive.box(labelsBoxName);
    } else {
      labelsBox = await Hive.openBox(labelsBoxName);
    }
    if (!labelsBox.containsKey('labels')) {
      await labelsBox.put('labels', <String>[]);
    }
    _labelsBoxes[inventoryId] = labelsBox;

    final String itemsBoxName = 'items_$inventoryId';
    Box<InventoryItem> itemsBox;
    if (Hive.isBoxOpen(itemsBoxName)) {
      itemsBox = Hive.box<InventoryItem>(itemsBoxName);
    } else {
      itemsBox = await Hive.openBox<InventoryItem>(itemsBoxName);
    }
    _itemsBoxes[inventoryId] = itemsBox;

    final String settingsBoxName = 'inventory_settings_$inventoryId';
    Box<InventorySettings> settingsBox;
    if (Hive.isBoxOpen(settingsBoxName)) {
      settingsBox = Hive.box<InventorySettings>(settingsBoxName);
    } else {
      settingsBox = await Hive.openBox<InventorySettings>(settingsBoxName);
    }
    if (!settingsBox.containsKey('main')) {
      await settingsBox.put('main', InventorySettings());
    }
    _settingsBoxes[inventoryId] = settingsBox;

    _currentInventoryId = inventoryId;
  }

  void selectInventory(String id) {
    _currentInventoryId = id;
  }

  Future<void> deleteInventoryData(String id) async {
    debugPrint('=== Deleting inventory data for: $id ===');
    
    Future<void> closeAndDeleteBox(String boxName) async {
      try {
        if (Hive.isBoxOpen(boxName)) {
          final box = Hive.box(boxName);
          await box.compact();
          await box.deleteFromDisk();
          debugPrint('Deleted box: $boxName');
        }
      } catch (e) {
        debugPrint('Error deleting box $boxName: $e');
      }
    }

    try {
      await closeAndDeleteBox('items_$id');
      _itemsBoxes.remove(id);

      await closeAndDeleteBox('labels_$id');
      _labelsBoxes.remove(id);

      await closeAndDeleteBox('inventory_settings_$id');
      _settingsBoxes.remove(id);

      if (_currentInventoryId == id) {
        _currentInventoryId = null;
      }

      debugPrint('=== Inventory data deleted successfully: $id ===');
    } catch (e) {
      debugPrint('=== Error deleting inventory data: $e ===');
    }
  }

  // ── Label Management ──────────────────────────────────────────

  List<String> get labels {
    if (_currentInventoryId == null || !_labelsBoxes.containsKey(_currentInventoryId!)) {
      return [];
    }
    final labelsData = _labelsBoxes[_currentInventoryId!]!.get('labels');
    return labelsData is List ? labelsData.cast<String>() : [];
  }

  bool get hasLabels => labels.isNotEmpty;
  bool hasLabel(String label) => labels.contains(label);

  Future<void> createLabel(String label) async {
    if (_currentInventoryId == null) return;

    if (!_labelsBoxes.containsKey(_currentInventoryId!)) {
      await initializeForInventory(_currentInventoryId!);
    }

    final currentLabels = List<String>.from(labels);
    if (!currentLabels.contains(label)) {
      currentLabels.add(label);
      await _labelsBoxes[_currentInventoryId!]!.put('labels', currentLabels);
      
      // Log activity
      final logEntry = ActivityLogEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        action: 'created',
        entityType: 'label',
        entityName: label,
        inventoryId: _currentInventoryId,
        inventoryName: getInventoryName(_currentInventoryId!),
        details: 'Label created: "$label"',
      );
      await ActivityLogService().addLog(logEntry);
    }
  }

  Future<void> renameLabel(String oldLabel, String newLabel) async {
    if (_currentInventoryId == null) return;

    if (!_labelsBoxes.containsKey(_currentInventoryId!)) {
      await initializeForInventory(_currentInventoryId!);
    }

    final currentLabels = List<String>.from(labels);
    final index = currentLabels.indexOf(oldLabel);
    if (index != -1) {
      currentLabels[index] = newLabel;
      await _labelsBoxes[_currentInventoryId!]!.put('labels', currentLabels);

      final items = getItemsByLabel(oldLabel);
      for (var item in items) {
        item.label = newLabel;
        await item.save();
      }
      
      // Log activity
      final logEntry = ActivityLogEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        action: 'modified',
        entityType: 'label',
        entityName: newLabel,
        inventoryId: _currentInventoryId,
        inventoryName: getInventoryName(_currentInventoryId!),
        details: 'Label renamed',
        changes: {
          'name': FieldChange(oldValue: oldLabel, newValue: newLabel),
        },
      );
      await ActivityLogService().addLog(logEntry);
    }
  }

  Future<void> deleteLabel(String label) async {
    if (_currentInventoryId == null) return;

    if (!_labelsBoxes.containsKey(_currentInventoryId!)) {
      await initializeForInventory(_currentInventoryId!);
    }

    final currentLabels = List<String>.from(labels);
    currentLabels.remove(label);
    await _labelsBoxes[_currentInventoryId!]!.put('labels', currentLabels);

    final items = getItemsByLabel(label);
    for (var item in items) {
      await item.delete();
    }
    
    // Log activity
    final logEntry = ActivityLogEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      action: 'deleted',
      entityType: 'label',
      entityName: label,
      inventoryId: _currentInventoryId,
      inventoryName: getInventoryName(_currentInventoryId!),
      details: 'Label deleted: "$label" with ${items.length} items',
    );
    await ActivityLogService().addLog(logEntry);
  }

  // ── Item Management ───────────────────────────────────────────

  List<InventoryItem> getItemsByLabel(String label) {
    if (_currentInventoryId == null || !_itemsBoxes.containsKey(_currentInventoryId!)) {
      return [];
    }
    return _itemsBoxes[_currentInventoryId!]!.values
        .where((item) => item.label == label)
        .toList();
  }

  List<InventoryItem> getItems(String label) => getItemsByLabel(label);

  Future<void> saveItem(InventoryItem item) async {
    if (_currentInventoryId == null || !_itemsBoxes.containsKey(_currentInventoryId!)) return;

    if (item.key != null) {
      await item.save();
    } else {
      await _itemsBoxes[_currentInventoryId!]!.add(item);
    }
  }

  Future<void> saveItems(String label, List<InventoryItem> newItems) async {
    if (_currentInventoryId == null) return;

    if (!_itemsBoxes.containsKey(_currentInventoryId!)) {
      await initializeForInventory(_currentInventoryId!);
    }

    final box = _itemsBoxes[_currentInventoryId!]!;
    final existingItems = box.values.where((i) => i.label == label).toList();

    final existingByKey = <int, InventoryItem>{};
    for (var item in existingItems) {
      if (item.key != null) {
        existingByKey[item.key!] = item;
      }
    }

    final keysUsed = <int>{};

    for (var item in newItems) {
      item.label = label;
      if (item.key != null && existingByKey.containsKey(item.key)) {
        await item.save();
        keysUsed.add(item.key!);
      } else {
        await box.add(item);
      }
    }

    for (var key in existingByKey.keys) {
      if (!keysUsed.contains(key)) {
        await existingByKey[key]!.delete();
      }
    }
  }

  Map<String, List<InventoryItem>> getAllItems() {
    final allItems = <String, List<InventoryItem>>{};
    if (_currentInventoryId == null) return allItems;

    for (var label in labels) {
      allItems[label] = getItemsByLabel(label);
    }
    return allItems;
  }

  // ── Inventory Name Lookup ─────────────────────────────────────

  Map<String, String> getAllInventoryNames() {
    final names = <String, String>{};
    try {
      final inventoriesListBox = Hive.box('inventories_list');
      for (var key in inventoriesListBox.keys) {
        final value = inventoriesListBox.get(key);
        if (value is Map) {
          final name = value['name'] as String? ?? 'Unknown Inventory';
          names[key] = name;
        }
      }
    } catch (e) {
      debugPrint('Error getting inventory names: $e');
    }
    return names;
  }

  String getInventoryName(String inventoryId) {
    try {
      final inventoriesListBox = Hive.box('inventories_list');
      final value = inventoriesListBox.get(inventoryId);
      if (value is Map) {
        return value['name'] as String? ?? inventoryId;
      }
    } catch (e) {
      debugPrint('Error getting inventory name: $e');
    }
    return inventoryId;
  }

  // ── Cross-Inventory Search ───────────────────────────────────

  List<Map<String, dynamic>> searchAllInventories(String query) {
    final results = <Map<String, dynamic>>[];
    final lowerQuery = query.toLowerCase().trim();

    if (lowerQuery.isEmpty) return results;

    final inventoryNames = getAllInventoryNames();

    final Set<String> allInventoryIds = {};
    allInventoryIds.addAll(_itemsBoxes.keys);
    allInventoryIds.addAll(inventoryNames.keys);

    for (var inventoryId in allInventoryIds) {
      try {
        Box<InventoryItem>? box;

        if (_itemsBoxes.containsKey(inventoryId)) {
          box = _itemsBoxes[inventoryId];
        } else {
          final boxName = 'items_$inventoryId';
          if (Hive.isBoxOpen(boxName)) {
            box = Hive.box<InventoryItem>(boxName);
          } else {
            continue;
          }
        }

        if (box == null || box.isEmpty) continue;

        final inventoryName = inventoryNames[inventoryId] ?? getInventoryName(inventoryId);

        for (var item in box.values) {
          if (_itemMatchesQuery(item, lowerQuery)) {
            results.add({
              'item': item,
              'inventoryId': inventoryId,
              'inventoryName': inventoryName,
            });
          }
        }
      } catch (e) {
        debugPrint('Error searching inventory $inventoryId: $e');
      }
    }

    results.sort((a, b) {
      final itemA = a['item'] as InventoryItem;
      final itemB = b['item'] as InventoryItem;

      final aNameMatch = itemA.name.toLowerCase() == lowerQuery;
      final bNameMatch = itemB.name.toLowerCase() == lowerQuery;

      if (aNameMatch && !bNameMatch) return -1;
      if (!aNameMatch && bNameMatch) return 1;

      return itemA.name.compareTo(itemB.name);
    });

    return results;
  }

  bool _itemMatchesQuery(InventoryItem item, String lowerQuery) {
    return item.name.toLowerCase().contains(lowerQuery) ||
        item.code.toLowerCase().contains(lowerQuery) ||
        item.barcode.toLowerCase().contains(lowerQuery) ||
        item.size.toLowerCase().contains(lowerQuery) ||
        item.label.toLowerCase().contains(lowerQuery) ||
        item.note.toLowerCase().contains(lowerQuery) ||
        item.color.toLowerCase().contains(lowerQuery) ||
        item.material.toLowerCase().contains(lowerQuery) ||
        item.customFields.values.any((v) => v.toLowerCase().contains(lowerQuery));
  }

  // ── Settings ─────────────────────────────────────────────────

  InventorySettings? get currentSettings {
    if (_currentInventoryId == null) return null;
    if (!_settingsBoxes.containsKey(_currentInventoryId!)) return null;

    final settings = _settingsBoxes[_currentInventoryId!]!.get('main');
    if (settings == null) {
      final defaultSettings = InventorySettings();
      _settingsBoxes[_currentInventoryId!]!.put('main', defaultSettings);
      return defaultSettings;
    }

    return settings;
  }

  Future<void> updateSettings(InventorySettings settings) async {
    if (_currentInventoryId == null) return;
    if (!_settingsBoxes.containsKey(_currentInventoryId!)) {
      await initializeForInventory(_currentInventoryId!);
    }
    
    // Get old settings for comparison
    final oldSettings = _settingsBoxes[_currentInventoryId!]!.get('main');
    
    await _settingsBoxes[_currentInventoryId!]!.put('main', settings);
    
    // Log settings change
    final changes = <String, FieldChange>{};
    if (oldSettings != null) {
      final oldFields = oldSettings.fieldConfigs
          .where((f) => f.isEnabled)
          .map((f) => '${f.fieldName}(${f.isRequired ? "required" : "optional"})')
          .join(', ');
      final newFields = settings.fieldConfigs
          .where((f) => f.isEnabled)
          .map((f) => '${f.fieldName}(${f.isRequired ? "required" : "optional"})')
          .join(', ');
      if (oldFields != newFields) {
        changes['fieldConfigs'] = FieldChange(oldValue: oldFields, newValue: newFields);
      }
      
      final oldCustom = oldSettings.customFieldNames.join(', ');
      final newCustom = settings.customFieldNames.join(', ');
      if (oldCustom != newCustom) {
        changes['customFields'] = FieldChange(oldValue: oldCustom, newValue: newCustom);
      }
    }
    
    final logEntry = ActivityLogEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      action: 'modified',
      entityType: 'settings',
      entityName: 'Settings',
      inventoryId: _currentInventoryId,
      inventoryName: getInventoryName(_currentInventoryId!),
      details: 'Settings updated',
      changes: changes.isNotEmpty ? changes : null,
    );
    await ActivityLogService().addLog(logEntry);
  }
}