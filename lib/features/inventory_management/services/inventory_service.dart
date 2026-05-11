import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';

class LabelInfo {
  final String name;
  final DateTime createdAt;
  final DateTime modifiedAt;

  LabelInfo({
    required this.name,
    required this.createdAt,
    DateTime? modifiedAt,
  }) : modifiedAt = modifiedAt ?? createdAt;

  Map<String, dynamic> toJson() => {
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt.toIso8601String(),
  };

  factory LabelInfo.fromJson(Map<String, dynamic> json) => LabelInfo(
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    modifiedAt: json['modifiedAt'] != null 
        ? DateTime.parse(json['modifiedAt'] as String) 
        : null,
  );
}

enum LabelSortType {
  nameAsc,
  nameDesc,
  dateCreatedAsc,
  dateCreatedDesc,
  dateModifiedAsc,
  dateModifiedDesc,
}

class InventoryService {
  final Map<String, Box<InventoryItem>> _itemsBoxes = {};
  final Map<String, Box> _labelsBoxes = {};
  final Map<String, Box<InventorySettings>> _settingsBoxes = {};

  String? _currentInventoryId;

  String? get currentInventoryId => _currentInventoryId;

  /// Check if a box is still open and available
  bool _isBoxAvailable(String boxType, String? inventoryId) {
    if (inventoryId == null) return false;
    switch (boxType) {
      case 'labels':
        return _labelsBoxes.containsKey(inventoryId) && _labelsBoxes[inventoryId]!.isOpen;
      case 'items':
        return _itemsBoxes.containsKey(inventoryId) && _itemsBoxes[inventoryId]!.isOpen;
      case 'settings':
        return _settingsBoxes.containsKey(inventoryId) && _settingsBoxes[inventoryId]!.isOpen;
      default:
        return false;
    }
  }

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
    if (!labelsBox.containsKey('labelInfos')) {
      await labelsBox.put('labelInfos', <String, Map<String, dynamic>>{});
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
      // Close boxes from our maps first
      if (_itemsBoxes.containsKey(id)) {
        try { await _itemsBoxes[id]!.close(); } catch (_) {}
        _itemsBoxes.remove(id);
      }
      if (_labelsBoxes.containsKey(id)) {
        try { await _labelsBoxes[id]!.close(); } catch (_) {}
        _labelsBoxes.remove(id);
      }
      if (_settingsBoxes.containsKey(id)) {
        try { await _settingsBoxes[id]!.close(); } catch (_) {}
        _settingsBoxes.remove(id);
      }

      // Then delete from disk
      await closeAndDeleteBox('items_$id');
      await closeAndDeleteBox('labels_$id');
      await closeAndDeleteBox('inventory_settings_$id');

      if (_currentInventoryId == id) {
        _currentInventoryId = null;
      }

      debugPrint('=== Inventory data deleted successfully: $id ===');
    } catch (e) {
      debugPrint('=== Error deleting inventory data: $e ===');
    }
  }

  // ── Label Management ──────────────────────────────────────────

  Map<String, LabelInfo> get labelInfos {
    if (_currentInventoryId == null || !_isBoxAvailable('labels', _currentInventoryId)) {
      return {};
    }
    final infosData = _labelsBoxes[_currentInventoryId!]!.get('labelInfos');
    if (infosData is Map) {
      return infosData.map((key, value) {
        if (value is Map) {
          return MapEntry(key.toString(), LabelInfo.fromJson(Map<String, dynamic>.from(value)));
        }
        return MapEntry(key.toString(), LabelInfo(name: key.toString(), createdAt: DateTime.now()));
      });
    }
    return {};
  }

  List<String> get labels {
    return getSortedLabels();
  }

  bool get hasLabels {
    if (_currentInventoryId == null || !_isBoxAvailable('labels', _currentInventoryId)) {
      return false;
    }
    final labelsData = _labelsBoxes[_currentInventoryId!]!.get('labels');
    return labelsData is List && labelsData.isNotEmpty;
  }

  bool hasLabel(String label) {
    if (_currentInventoryId == null || !_isBoxAvailable('labels', _currentInventoryId)) {
      return false;
    }
    final labelsData = _labelsBoxes[_currentInventoryId!]!.get('labels');
    return labelsData is List && labelsData.contains(label);
  }

  List<String> getSortedLabels({LabelSortType sortType = LabelSortType.nameAsc}) {
    if (_currentInventoryId == null || !_isBoxAvailable('labels', _currentInventoryId)) {
      return [];
    }
    final infos = labelInfos;
    if (infos.isEmpty) return [];

    final sortedEntries = infos.entries.toList();
    
    switch (sortType) {
      case LabelSortType.nameAsc:
        sortedEntries.sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
        break;
      case LabelSortType.nameDesc:
        sortedEntries.sort((a, b) => b.key.toLowerCase().compareTo(a.key.toLowerCase()));
        break;
      case LabelSortType.dateCreatedAsc:
        sortedEntries.sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
        break;
      case LabelSortType.dateCreatedDesc:
        sortedEntries.sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));
        break;
      case LabelSortType.dateModifiedAsc:
        sortedEntries.sort((a, b) => a.value.modifiedAt.compareTo(b.value.modifiedAt));
        break;
      case LabelSortType.dateModifiedDesc:
        sortedEntries.sort((a, b) => b.value.modifiedAt.compareTo(a.value.modifiedAt));
        break;
    }
    
    return sortedEntries.map((e) => e.key).toList();
  }

  LabelInfo? getLabelInfo(String labelName) {
    if (_currentInventoryId == null || !_isBoxAvailable('labels', _currentInventoryId)) {
      return null;
    }
    return labelInfos[labelName];
  }

  Future<void> createLabel(String label) async {
    if (_currentInventoryId == null) return;

    if (!_labelsBoxes.containsKey(_currentInventoryId!)) {
      await initializeForInventory(_currentInventoryId!);
    }

    final currentLabels = _getCurrentLabelsList();
    if (!currentLabels.contains(label)) {
      currentLabels.add(label);
      await _labelsBoxes[_currentInventoryId!]!.put('labels', currentLabels);
      
      final now = DateTime.now();
      final infos = Map<String, dynamic>.from(
        _labelsBoxes[_currentInventoryId!]!.get('labelInfos', defaultValue: <String, Map<String, dynamic>>{}) as Map
      );
      infos[label] = LabelInfo(name: label, createdAt: now, modifiedAt: now).toJson();
      await _labelsBoxes[_currentInventoryId!]!.put('labelInfos', infos);
      
      final logEntry = ActivityLogEntry(
        id: now.microsecondsSinceEpoch.toString(),
        timestamp: now,
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

    final currentLabels = _getCurrentLabelsList();
    final index = currentLabels.indexOf(oldLabel);
    if (index != -1) {
      currentLabels[index] = newLabel;
      await _labelsBoxes[_currentInventoryId!]!.put('labels', currentLabels);

      final infos = Map<String, dynamic>.from(
        _labelsBoxes[_currentInventoryId!]!.get('labelInfos', defaultValue: <String, Map<String, dynamic>>{}) as Map
      );
      final oldInfo = infos[oldLabel];
      if (oldInfo is Map) {
        final labelInfo = LabelInfo.fromJson(Map<String, dynamic>.from(oldInfo));
        infos.remove(oldLabel);
        infos[newLabel] = LabelInfo(
          name: newLabel,
          createdAt: labelInfo.createdAt,
          modifiedAt: DateTime.now(),
        ).toJson();
        await _labelsBoxes[_currentInventoryId!]!.put('labelInfos', infos);
      }

      final items = getItemsByLabel(oldLabel);
      for (var item in items) {
        item.label = newLabel;
        await item.save();
      }
      
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

    final currentLabels = _getCurrentLabelsList();
    currentLabels.remove(label);
    await _labelsBoxes[_currentInventoryId!]!.put('labels', currentLabels);

    final infos = Map<String, dynamic>.from(
      _labelsBoxes[_currentInventoryId!]!.get('labelInfos', defaultValue: <String, Map<String, dynamic>>{}) as Map
    );
    infos.remove(label);
    await _labelsBoxes[_currentInventoryId!]!.put('labelInfos', infos);

    final items = getItemsByLabel(label);
    for (var item in items) {
      await item.delete();
    }
    
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

  List<String> _getCurrentLabelsList() {
    final labelsData = _labelsBoxes[_currentInventoryId!]!.get('labels');
    return labelsData is List ? List<String>.from(labelsData.cast<String>()) : [];
  }

  // ── Item Management ───────────────────────────────────────────

  List<InventoryItem> getItemsByLabel(String label) {
    if (_currentInventoryId == null || !_isBoxAvailable('items', _currentInventoryId)) {
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

  Future<int> importItems(String label, List<InventoryItem> newItems) async {
    if (_currentInventoryId == null) return 0;

    if (!_itemsBoxes.containsKey(_currentInventoryId!)) {
      await initializeForInventory(_currentInventoryId!);
    }

    final box = _itemsBoxes[_currentInventoryId!]!;
    final existingItems = box.values.where((i) => i.label == label).toList();
    int importedCount = 0;

    for (var newItem in newItems) {
      newItem.label = label;
      
      bool isDuplicate = existingItems.any((existing) =>
        existing.name == newItem.name &&
        existing.code == newItem.code &&
        existing.barcode == newItem.barcode &&
        existing.quantity == newItem.quantity &&
        existing.size == newItem.size &&
        existing.color == newItem.color &&
        existing.material == newItem.material &&
        existing.note == newItem.note
      );

      if (!isDuplicate) {
        await box.add(newItem);
        importedCount++;
      }
    }

    return importedCount;
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
    if (_currentInventoryId == null || !_isBoxAvailable('settings', _currentInventoryId)) return null;
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
    
    final oldSettings = _settingsBoxes[_currentInventoryId!]!.get('main');
    await _settingsBoxes[_currentInventoryId!]!.put('main', settings);
    
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