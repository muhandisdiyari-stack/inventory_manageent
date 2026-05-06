import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';

class InventoryService {
  final Map<String, Box<InventoryItem>> _itemsBoxes = {};
  final Map<String, Box> _labelsBoxes = {};
  final Map<String, Box<InventorySettings>> _settingsBoxes = {};

  String? _currentInventoryId;

  String? get currentInventoryId => _currentInventoryId;

  Future<void> initializeForInventory(String inventoryId) async {
    Box labelsBox;
    if (Hive.isBoxOpen('labels_$inventoryId')) {
      labelsBox = Hive.box('labels_$inventoryId');
    } else {
      labelsBox = await Hive.openBox('labels_$inventoryId');
    }
    if (!labelsBox.containsKey('labels')) {
      await labelsBox.put('labels', <String>[]);
    }
    _labelsBoxes[inventoryId] = labelsBox;

    Box<InventoryItem> itemsBox;
    if (Hive.isBoxOpen('items_$inventoryId')) {
      itemsBox = Hive.box<InventoryItem>('items_$inventoryId');
    } else {
      itemsBox = await Hive.openBox<InventoryItem>('items_$inventoryId');
    }
    _itemsBoxes[inventoryId] = itemsBox;

    Box<InventorySettings> settingsBox;
    if (Hive.isBoxOpen('inventory_settings_$inventoryId')) {
      settingsBox = Hive.box<InventorySettings>('inventory_settings_$inventoryId');
    } else {
      settingsBox = await Hive.openBox<InventorySettings>('inventory_settings_$inventoryId');
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
    
    try {
      if (_itemsBoxes.containsKey(id)) {
        debugPrint('Clearing items box...');
        try {
          await _itemsBoxes[id]!.clear();
          await _itemsBoxes[id]!.deleteFromDisk();
        } catch (e) {
          debugPrint('Error clearing items: $e');
          final boxName = 'items_$id';
          if (Hive.isBoxOpen(boxName)) {
            await Hive.box(boxName).deleteFromDisk();
          }
        }
        _itemsBoxes.remove(id);
      } else {
        final boxName = 'items_$id';
        if (Hive.isBoxOpen(boxName)) {
          debugPrint('Deleting uncached items box...');
          await Hive.box(boxName).deleteFromDisk();
        }
      }
      
      if (_labelsBoxes.containsKey(id)) {
        debugPrint('Clearing labels box...');
        try {
          await _labelsBoxes[id]!.clear();
          await _labelsBoxes[id]!.deleteFromDisk();
        } catch (e) {
          debugPrint('Error clearing labels: $e');
          final boxName = 'labels_$id';
          if (Hive.isBoxOpen(boxName)) {
            await Hive.box(boxName).deleteFromDisk();
          }
        }
        _labelsBoxes.remove(id);
      } else {
        final boxName = 'labels_$id';
        if (Hive.isBoxOpen(boxName)) {
          debugPrint('Deleting uncached labels box...');
          await Hive.box(boxName).deleteFromDisk();
        }
      }
      
      if (_settingsBoxes.containsKey(id)) {
        debugPrint('Clearing settings box...');
        try {
          await _settingsBoxes[id]!.clear();
          await _settingsBoxes[id]!.deleteFromDisk();
        } catch (e) {
          debugPrint('Error clearing settings: $e');
          final boxName = 'inventory_settings_$id';
          if (Hive.isBoxOpen(boxName)) {
            await Hive.box(boxName).deleteFromDisk();
          }
        }
        _settingsBoxes.remove(id);
      } else {
        final boxName = 'inventory_settings_$id';
        if (Hive.isBoxOpen(boxName)) {
          debugPrint('Deleting uncached settings box...');
          await Hive.box(boxName).deleteFromDisk();
        }
      }
      
      if (_currentInventoryId == id) {
        _currentInventoryId = null;
      }
      
      debugPrint('=== Inventory data deleted successfully: $id ===');
    } catch (e) {
      debugPrint('=== Error deleting inventory data: $e ===');
      rethrow;
    }
  }

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
  }

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
    await _settingsBoxes[_currentInventoryId!]!.put('main', settings);
  }
}