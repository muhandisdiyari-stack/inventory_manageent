import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import '../../../core/models/label.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';
import '../../../core/config/app_config.dart';

const _uuid = Uuid();

// ─── Sort Type Enum ───────────────────────────────────────────────

enum LabelSortType {
  nameAsc,
  nameDesc,
  dateCreatedAsc,
  dateCreatedDesc,
  dateModifiedAsc,
  dateModifiedDesc,
}

// ─── Inventory Service ────────────────────────────────────────────
//
// Architecture:
//   Supabase is the AUTHORITATIVE source of truth.
//   Hive is used ONLY as a performance cache.
//   On every initializeForInventory(), we pull fresh data from Supabase
//   and overwrite the Hive cache. This prevents stale data, ghost records,
//   and lost updates.

class InventoryService {
  final Map<String, Box<InventoryItem>> _itemsBoxes = {};
  final Map<String, Box> _labelsBoxes = {};
  final Map<String, Box<InventorySettings>> _settingsBoxes = {};

  // In-memory label cache for fast access
  final Map<String, List<Label>> _labelsCache = {};

  String? _currentInventoryId;
  String? _currentCompanyId;
  bool _isInitializing = false;

  String? get currentInventoryId => _currentInventoryId;
  String? get currentCompanyId => _currentCompanyId;
  bool get isInitializing => _isInitializing;

  // ─── Initialization ─────────────────────────────────────────────

  /// Initialize the service for a specific inventory.
  ///
  /// This ALWAYS pulls fresh data from Supabase first (if available),
  /// then caches it in Hive for offline/performance use.
  Future<void> initializeForInventory(String inventoryId) async {
    if (_isInitializing && _currentInventoryId == inventoryId) return;

    _isInitializing = true;

    try {
      // Flush and close all previously open boxes
      await _closeAllBoxes();

      // Open labels box
      final String labelsBoxName = 'labels_$inventoryId';
      final labelsBox = await Hive.openBox(labelsBoxName);
      _labelsBoxes[inventoryId] = labelsBox;

      // Open items box
      final String itemsBoxName = 'items_$inventoryId';
      final itemsBox = await Hive.openBox<InventoryItem>(itemsBoxName);
      _itemsBoxes[inventoryId] = itemsBox;

      // Open settings box
      final String settingsBoxName = 'inventory_settings_$inventoryId';
      final settingsBox =
          await Hive.openBox<InventorySettings>(settingsBoxName);
      if (!settingsBox.containsKey('main')) {
        await settingsBox.put('main', InventorySettings());
      }
      _settingsBoxes[inventoryId] = settingsBox;

      _currentInventoryId = inventoryId;
      _labelsCache.remove(inventoryId);

      // Load company ID for tenant isolation
      await _loadCompanyId();

      // 🔑 Sync from Supabase (authoritative) → overwrite Hive cache
      if (AppConfig.useSupabase && _currentCompanyId != null) {
        await _syncLabelsFromSupabase(inventoryId);
        await _syncItemsFromSupabase(inventoryId);
      } else {
        // Offline: load from Hive cache
        _loadLabelsFromCache(inventoryId);
      }

      debugPrint(
          '✅ Inventory $inventoryId initialized (${_labelsCache[inventoryId]?.length ?? 0} labels)');
    } catch (e) {
      debugPrint('❌ Error initializing inventory $inventoryId: $e');
      // Try to load from cache on error
      _loadLabelsFromCache(inventoryId);
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _closeAllBoxes() async {
    for (final box in [..._itemsBoxes.values]) {
      try {
        await box.flush();
        await box.close();
      } catch (_) {}
    }
    for (final box in [..._labelsBoxes.values]) {
      try {
        await box.flush();
        await box.close();
      } catch (_) {}
    }
    for (final box in [..._settingsBoxes.values]) {
      try {
        await box.flush();
        await box.close();
      } catch (_) {}
    }
    _itemsBoxes.clear();
    _labelsBoxes.clear();
    _settingsBoxes.clear();
    _labelsCache.clear();
  }

  Future<void> _loadCompanyId() async {
    if (!AppConfig.useSupabase) return;
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      final profileData = await client
          .from('profiles')
          .select('company_id')
          .eq('id', user.id)
          .maybeSingle();

      _currentCompanyId = profileData?['company_id'] as String?;
      debugPrint('📋 Loaded company ID: $_currentCompanyId');
    } catch (e) {
      debugPrint('⚠️ Could not load company ID: $e');
      _currentCompanyId = null;
    }
  }

  void selectInventory(String id) {
    _currentInventoryId = id;
  }

  // ─── Supabase Sync (AUTHORITATIVE SOURCE) ──────────────────────

  /// Fetches labels from Supabase and overwrites the Hive cache.
  Future<void> _syncLabelsFromSupabase(String inventoryId) async {
    if (!AppConfig.useSupabase) return;
    final companyId = _currentCompanyId;
    if (companyId == null) return;

    try {
      final client = Supabase.instance.client;

      final data = await client
          .from('labels')
          .select()
          .eq('company_id', companyId)
          .eq('is_deleted', false)
          .order('name');

      final labels = data
          .map((row) => Label.fromSupabase(Map<String, dynamic>.from(row)))
          .toList();

      // Cache to Hive
      final box = _labelsBoxes[inventoryId];
      if (box != null) {
        final cacheData = labels.map((l) => l.toLocalJson()).toList();
        await box.put('labels_cache', cacheData);
        await box.put('label_names', labels.map((l) => l.name).toList());
      }

      _labelsCache[inventoryId] = labels;
      debugPrint('🔄 Synced ${labels.length} labels from Supabase');
    } catch (e) {
      debugPrint('⚠️ Label sync error: $e');
      _loadLabelsFromCache(inventoryId);
    }
  }

  void _loadLabelsFromCache(String inventoryId) {
    final box = _labelsBoxes[inventoryId];
    if (box == null) {
      _labelsCache[inventoryId] = [];
      return;
    }

    final raw = box.get('labels_cache');
    if (raw is List && raw.isNotEmpty) {
      _labelsCache[inventoryId] = raw
          .map((e) => Label.fromLocalJson(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      _labelsCache[inventoryId] = [];
    }
  }

  /// Fetches items from Supabase and overwrites the Hive cache.
  Future<void> _syncItemsFromSupabase(String inventoryId) async {
    if (!AppConfig.useSupabase) return;
    final companyId = _currentCompanyId;
    if (companyId == null) return;

    try {
      final client = Supabase.instance.client;

      final data = await client
          .from('inventory_items')
          .select()
          .eq('company_id', companyId)
          .eq('inventory_id', inventoryId)
          .eq('is_deleted', false)
          .order('updated_at', ascending: false);

      final box = _itemsBoxes[inventoryId];
      if (box == null) return;

      // Clear local cache and repopulate from Supabase
      await box.clear();

      for (final itemData in data) {
        final item =
            _itemFromSupabaseRow(Map<String, dynamic>.from(itemData));
        item.customFields['_supabase_id'] =
            itemData['id'] as String? ?? '';
        await box.add(item);
      }

      debugPrint('🔄 Synced ${data.length} items from Supabase');
    } catch (e) {
      debugPrint('⚠️ Item sync error: $e');
      // Keep existing cache on error
    }
  }

  InventoryItem _itemFromSupabaseRow(Map<String, dynamic> row) {
    final customFields = <String, String>{};
    final rawCustom = row['custom_fields'];
    if (rawCustom is Map) {
      for (final entry in rawCustom.entries) {
        customFields[entry.key.toString()] = entry.value.toString();
      }
    }

    return InventoryItem(
      name: row['name'] as String? ?? '',
      code: row['code'] as String? ?? '',
      barcode: row['barcode'] as String? ?? '',
      color: row['color'] as String? ?? '',
      material: row['material'] as String? ?? '',
      size: row['size'] as String? ?? '',
      quantity: row['quantity'] as int? ?? 0,
      label: row['label'] as String? ?? '',
      note: row['note'] as String? ?? '',
      customFields: customFields,
      productionDate: row['production_date'] != null
          ? DateTime.tryParse(row['production_date'] as String)
          : null,
      expireDate: row['expire_date'] != null
          ? DateTime.tryParse(row['expire_date'] as String)
          : null,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      modified: row['updated_at'] != null
          ? DateTime.parse(row['updated_at'] as String)
          : DateTime.now(),
    );
  }

  // ─── Label Accessors ───────────────────────────────────────────

  /// Returns all labels for the current inventory (from cache).
  List<Label> get labels {
    if (_currentInventoryId == null) return [];
    return _labelsCache[_currentInventoryId!] ?? [];
  }

  /// Returns just the label names (for backward compatibility with UI).
  List<String> get labelNames => labels.map((l) => l.name).toList();

  /// Returns labels sorted by the given criteria.
  List<Label> getSortedLabels(
      {LabelSortType sortType = LabelSortType.nameAsc}) {
    final all = List<Label>.from(labels);
    switch (sortType) {
      case LabelSortType.nameAsc:
        all.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case LabelSortType.nameDesc:
        all.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case LabelSortType.dateCreatedAsc:
        all.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case LabelSortType.dateCreatedDesc:
        all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case LabelSortType.dateModifiedAsc:
        all.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case LabelSortType.dateModifiedDesc:
        all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return all;
  }

  /// Returns sorted label names (for backward compatibility).
  List<String> getSortedLabelNames(
      {LabelSortType sortType = LabelSortType.nameAsc}) {
    return getSortedLabels(sortType: sortType).map((l) => l.name).toList();
  }

  Label? getLabelById(String id) {
    try {
      return labels.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  Label? getLabelByName(String name) {
    try {
      return labels.firstWhere((l) => l.name == name);
    } catch (_) {
      return null;
    }
  }

  bool get hasLabels => labels.isNotEmpty;

  bool hasLabel(String name) => labels.any((l) => l.name == name);

  // ─── Label CRUD (Supabase-Authoritative) ───────────────────────

  /// Creates a label. Writes to Supabase FIRST, then updates cache.
  Future<Label> createLabel(String name) async {
    if (_currentInventoryId == null) throw Exception('No inventory selected');
    final companyId = _currentCompanyId;
    if (companyId == null) throw Exception('No company selected');

    final user = Supabase.instance.client.auth.currentUser;
    final now = DateTime.now();

    if (AppConfig.useSupabase) {
      final response = await Supabase.instance.client
          .from('labels')
          .insert({
            'company_id': companyId,
            'inventory_id': _currentInventoryId,
            'name': name,
            'created_by': user?.id,
            'created_by_name':
                user?.userMetadata?['display_name'] ?? user?.email ?? 'Unknown',
            'created_at': now.toUtc().toIso8601String(),
            'updated_at': now.toUtc().toIso8601String(),
          })
          .select()
          .single();

      final label = Label.fromSupabase(Map<String, dynamic>.from(response));
      _addLabelToCache(label);

      await ActivityLogService().addLog(ActivityLogEntry(
        id: _uuid.v4(),
        timestamp: now,
        action: 'created',
        entityType: 'label',
        entityName: name,
        inventoryId: _currentInventoryId,
        inventoryName: getInventoryName(_currentInventoryId!),
        details: 'Label created: "$name"',
      ));

      return label;
    }

    // Offline fallback
    final label = Label.create(
      name: name,
      companyId: companyId,
      inventoryId: _currentInventoryId!,
      createdBy: 'offline',
      createdByName: 'Offline User',
    );
    _addLabelToCache(label);
    return label;
  }

  void _addLabelToCache(Label label) {
    final list = List<Label>.from(labels);
    final existingIndex = list.indexWhere((l) => l.id == label.id);
    if (existingIndex != -1) {
      list[existingIndex] = label;
    } else {
      list.add(label);
    }
    _labelsCache[_currentInventoryId!] = list;
  }

  /// Renames a label. Updates Supabase FIRST, then updates cache.
  Future<void> renameLabel(String oldName, String newName) async {
    if (_currentInventoryId == null) throw Exception('No inventory selected');

    final label = getLabelByName(oldName);
    if (label == null) throw Exception('Label "$oldName" not found');

    if (AppConfig.useSupabase) {
      await Supabase.instance.client.from('labels').update({
        'name': newName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', label.id);
    }

    // Update cache
    final list = List<Label>.from(labels);
    final index = list.indexWhere((l) => l.id == label.id);
    if (index != -1) {
      list[index] = label.copyWith(name: newName);
      _labelsCache[_currentInventoryId!] = list;
    }

    // Update all items referencing this label name
    final items = getItemsByLabel(oldName);
    for (final item in items) {
      item.label = newName;
      await item.save();
    }

    await ActivityLogService().addLog(ActivityLogEntry(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      action: 'modified',
      entityType: 'label',
      entityName: newName,
      inventoryId: _currentInventoryId,
      inventoryName: getInventoryName(_currentInventoryId!),
      details: 'Label renamed',
      changes: {
        'name': FieldChange(oldValue: oldName, newValue: newName),
      },
    ));
  }

  /// Soft-deletes a label and all its items.
  Future<void> deleteLabel(String name) async {
    if (_currentInventoryId == null) throw Exception('No inventory selected');

    final label = getLabelByName(name);
    if (label == null) return;

    final companyId = _currentCompanyId;

    if (AppConfig.useSupabase && companyId != null) {
      // Soft-delete label in Supabase
      await Supabase.instance.client.from('labels').update({
        'is_deleted': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', label.id);

      // Soft-delete associated items
      await Supabase.instance.client
          .from('inventory_items')
          .update({'is_deleted': true})
          .eq('company_id', companyId)
          .eq('label', name);
    }

    // Remove from cache
    final list = List<Label>.from(labels);
    list.removeWhere((l) => l.id == label.id);
    _labelsCache[_currentInventoryId!] = list;

    // Delete local items
    final items = getItemsByLabel(name);
    for (final item in items) {
      await item.delete();
    }

    await ActivityLogService().addLog(ActivityLogEntry(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      action: 'deleted',
      entityType: 'label',
      entityName: name,
      inventoryId: _currentInventoryId,
      inventoryName: getInventoryName(_currentInventoryId!),
      details: 'Label deleted: "$name" with ${items.length} items',
    ));
  }

  // ─── Item Management ───────────────────────────────────────────

  List<InventoryItem> getItemsByLabel(String label) {
    if (_currentInventoryId == null ||
        !_itemsBoxes.containsKey(_currentInventoryId!)) {
      return [];
    }
    return _itemsBoxes[_currentInventoryId!]!
        .values
        .where((item) => item.label == label)
        .toList();
  }

  List<InventoryItem> getItems(String label) => getItemsByLabel(label);

  Future<void> saveItem(InventoryItem item) async {
    if (_currentInventoryId == null) return;

    final box = _itemsBoxes[_currentInventoryId!];
    if (box == null) return;

    if (item.key != null) {
      await item.save();
    } else {
      await box.add(item);
    }

    await _syncItemToSupabase(item);
  }

  Future<void> _syncItemToSupabase(InventoryItem item) async {
    if (!AppConfig.useSupabase) return;
    final companyId = _currentCompanyId;
    if (companyId == null || _currentInventoryId == null) return;

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      final now = DateTime.now().toUtc().toIso8601String();

      final data = <String, dynamic>{
        'company_id': companyId,
        'inventory_id': _currentInventoryId,
        'name': item.name,
        'code': item.code,
        'barcode': item.barcode,
        'color': item.color,
        'material': item.material,
        'size': item.size,
        'quantity': item.quantity,
        'label': item.label,
        'note': item.note,
        'custom_fields': item.customFields,
        'production_date': item.productionDate?.toIso8601String(),
        'expire_date': item.expireDate?.toIso8601String(),
        'created_by': user?.id,
        'created_by_name':
            user?.userMetadata?['display_name'] ?? user?.email ?? 'Unknown',
        'updated_at': now,
      };

      final supabaseId = item.customFields['_supabase_id'];

      if (supabaseId != null && supabaseId.isNotEmpty) {
        await client.from('inventory_items').update(data).eq('id', supabaseId);
        debugPrint('🔄 Item updated: ${item.name}');
      } else {
        final newId = _uuid.v4();
        data['id'] = newId;
        data['created_at'] = item.createdAt.toUtc().toIso8601String();
        await client.from('inventory_items').insert(data);
        item.customFields['_supabase_id'] = newId;
        await item.save();
        debugPrint('✅ New item synced: ${item.name}');
      }
    } catch (e) {
      debugPrint('❌ Sync error for ${item.name}: $e');
    }
  }

  Future<int> importItems(String label, List<InventoryItem> newItems) async {
    if (_currentInventoryId == null) return 0;

    final box = _itemsBoxes[_currentInventoryId!];
    if (box == null) return 0;

    final existingItems =
        box.values.where((i) => i.label == label).toList();
    int importedCount = 0;

    for (final newItem in newItems) {
      newItem.label = label;

      final isDuplicate = existingItems.any((existing) =>
          existing.name == newItem.name &&
          existing.code == newItem.code &&
          existing.barcode == newItem.barcode &&
          existing.quantity == newItem.quantity);

      if (!isDuplicate) {
        await box.add(newItem);
        await _syncItemToSupabase(newItem);
        importedCount++;
      }
    }

    return importedCount;
  }

  Map<String, List<InventoryItem>> getAllItems() {
    final allItems = <String, List<InventoryItem>>{};
    if (_currentInventoryId == null) return allItems;
    for (final label in labelNames) {
      allItems[label] = getItemsByLabel(label);
    }
    return allItems;
  }

  // ─── Inventory Names ───────────────────────────────────────────

  Map<String, String> getAllInventoryNames() {
    final names = <String, String>{};
    try {
      final box = Hive.box('inventories_list');
      for (final key in box.keys) {
        final value = box.get(key);
        if (value is Map) {
          final map = Map<String, dynamic>.from(value);
          names[key.toString()] =
              map['name'] as String? ?? 'Unknown Inventory';
        }
      }
    } catch (e) {
      debugPrint('Error getting inventory names: $e');
    }
    return names;
  }

  String getInventoryName(String inventoryId) {
    try {
      final box = Hive.box('inventories_list');
      final value = box.get(inventoryId);
      if (value is Map) {
        return Map<String, dynamic>.from(value)['name'] as String? ??
            inventoryId;
      }
    } catch (_) {}
    return inventoryId;
  }

  // ─── Search ────────────────────────────────────────────────────

  List<Map<String, dynamic>> searchAllInventories(String query) {
    final results = <Map<String, dynamic>>[];
    final lowerQuery = query.toLowerCase().trim();
    if (lowerQuery.isEmpty) return results;

    final inventoryNames = getAllInventoryNames();
    final allIds = <String>{};
    allIds.addAll(_itemsBoxes.keys);
    allIds.addAll(inventoryNames.keys);

    for (final inventoryId in allIds) {
      try {
        Box<InventoryItem>? box;
        if (_itemsBoxes.containsKey(inventoryId)) {
          box = _itemsBoxes[inventoryId];
        } else {
          final boxName = 'items_$inventoryId';
          if (Hive.isBoxOpen(boxName)) {
            box = Hive.box<InventoryItem>(boxName);
          }
        }
        if (box == null || box.isEmpty) continue;

        final invName =
            inventoryNames[inventoryId] ?? getInventoryName(inventoryId);

        for (final item in box.values) {
          if (item.matchesQuery(lowerQuery)) {
            results.add({
              'item': item,
              'inventoryId': inventoryId,
              'inventoryName': invName,
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
      if (itemA.name.toLowerCase() == lowerQuery) return -1;
      if (itemB.name.toLowerCase() == lowerQuery) return 1;
      return itemA.name.compareTo(itemB.name);
    });

    return results;
  }

  // ─── Settings ──────────────────────────────────────────────────

  InventorySettings? get currentSettings {
    if (_currentInventoryId == null ||
        !_settingsBoxes.containsKey(_currentInventoryId!)) {
      return null;
    }
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

    await _settingsBoxes[_currentInventoryId!]!.put('main', settings);

    await ActivityLogService().addLog(ActivityLogEntry(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      action: 'modified',
      entityType: 'settings',
      entityName: 'Settings',
      inventoryId: _currentInventoryId,
      inventoryName: getInventoryName(_currentInventoryId!),
      details: 'Settings updated',
    ));
  }

  // ─── Inventory Deletion ─────────────────────────────────────────

  Future<void> deleteInventoryData(String id) async {
    debugPrint('=== Deleting inventory data for: $id ===');

    try {
      for (final box in [
        _itemsBoxes[id],
        _labelsBoxes[id],
        _settingsBoxes[id]
      ]) {
        if (box != null) {
          try {
            await box.flush();
            await box.close();
          } catch (_) {}
        }
      }

      _itemsBoxes.remove(id);
      _labelsBoxes.remove(id);
      _settingsBoxes.remove(id);
      _labelsCache.remove(id);

      await _deleteBoxSafely('items_$id');
      await _deleteBoxSafely('labels_$id');
      await _deleteBoxSafely('inventory_settings_$id');

      if (_currentInventoryId == id) {
        _currentInventoryId = null;
      }

      if (AppConfig.useSupabase && _currentCompanyId != null) {
        try {
          await Supabase.instance.client
              .from('inventory_items')
              .delete()
              .eq('inventory_id', id)
              .eq('company_id', _currentCompanyId!);
        } catch (e) {
          debugPrint('Supabase cleanup error: $e');
        }
      }

      debugPrint('=== Inventory data deleted: $id ===');
    } catch (e) {
      debugPrint('=== Error deleting inventory data: $e ===');
      rethrow;
    }
  }

  Future<void> _deleteBoxSafely(String boxName) async {
    try {
      await Hive.deleteBoxFromDisk(boxName);
      debugPrint('Deleted box: $boxName');
    } catch (e) {
      debugPrint('Error deleting box $boxName: $e');
    }
  }

  // ─── Cleanup ───────────────────────────────────────────────────

  Future<void> dispose() async {
    await _closeAllBoxes();
    _currentInventoryId = null;
    _currentCompanyId = null;
  }
}