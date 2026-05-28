import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import '../../../core/models/label.dart';
import '../../../core/config/app_config.dart';

const _uuid = Uuid();

enum LabelSortType {
  nameAsc, nameDesc, dateCreatedAsc, dateCreatedDesc, dateModifiedAsc, dateModifiedDesc,
}

class InventoryService {
  final Map<String, Box<InventoryItem>> _itemsBoxes = {};
  final Map<String, Box> _labelsBoxes = {};
  final Map<String, Box<InventorySettings>> _settingsBoxes = {};
  final Map<String, List<Label>> _labelsCache = {};

  String? _currentInventoryId;
  String? _currentCompanyId;
  bool _isInitializing = false;

  String? get currentInventoryId => _currentInventoryId;
  String? get currentCompanyId => _currentCompanyId;

  // ─── Initialization ─────────────────────────────────────────────

  Future<void> initializeForInventory(String inventoryId) async {
    if (_isInitializing && _currentInventoryId == inventoryId) return;
    _isInitializing = true;

    try {
      await _closeAllBoxes();

      _labelsBoxes[inventoryId] = await Hive.openBox('labels_$inventoryId');
      _itemsBoxes[inventoryId] = await Hive.openBox<InventoryItem>('items_$inventoryId');
      final settingsBox = await Hive.openBox<InventorySettings>('inventory_settings_$inventoryId');
      if (!settingsBox.containsKey('main')) {
        await settingsBox.put('main', InventorySettings());
      }
      _settingsBoxes[inventoryId] = settingsBox;

      _currentInventoryId = inventoryId;
      _labelsCache.remove(inventoryId);

      await _loadCompanyId();

      if (AppConfig.useSupabase && _currentCompanyId != null) {
        await _syncLabelsFromSupabase(inventoryId);
        await _syncItemsFromSupabase(inventoryId);
      } else {
        _loadLabelsFromCache(inventoryId);
      }
    } catch (e) {
      debugPrint('❌ Error initializing inventory $inventoryId: $e');
      _loadLabelsFromCache(inventoryId);
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _closeAllBoxes() async {
    for (final box in [..._itemsBoxes.values, ..._labelsBoxes.values, ..._settingsBoxes.values]) {
      try { await box.flush(); await box.close(); } catch (_) {}
    }
    _itemsBoxes.clear();
    _labelsBoxes.clear();
    _settingsBoxes.clear();
    _labelsCache.clear();
  }

  Future<void> _loadCompanyId() async {
    if (!AppConfig.useSupabase) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final data = await Supabase.instance.client
          .from('profiles').select('company_id').eq('id', user.id).maybeSingle();
      _currentCompanyId = data?['company_id'] as String?;
    } catch (e) {
      _currentCompanyId = null;
    }
  }

  // ─── Supabase Sync ──────────────────────────────────────────────

  Future<void> _syncLabelsFromSupabase(String inventoryId) async {
    if (!AppConfig.useSupabase) return;
    final companyId = _currentCompanyId;
    if (companyId == null) return;

    try {
      final data = await Supabase.instance.client
          .from('labels')
          .select()
          .eq('company_id', companyId)
          .eq('is_deleted', false)
          .order('name');

      final labels = data.map((row) => Label.fromSupabase(Map<String, dynamic>.from(row))).toList();
      final box = _labelsBoxes[inventoryId];
      if (box != null) {
        await box.put('labels_cache', labels.map((l) => l.toLocalJson()).toList());
        await box.put('label_names', labels.map((l) => l.name).toList());
      }
      _labelsCache[inventoryId] = labels;
    } catch (e) {
      _loadLabelsFromCache(inventoryId);
    }
  }

  void _loadLabelsFromCache(String inventoryId) {
    final box = _labelsBoxes[inventoryId];
    if (box == null) { _labelsCache[inventoryId] = []; return; }
    final raw = box.get('labels_cache');
    if (raw is List && raw.isNotEmpty) {
      _labelsCache[inventoryId] = raw
          .map((e) => Label.fromLocalJson(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      _labelsCache[inventoryId] = [];
    }
  }

  Future<void> _syncItemsFromSupabase(String inventoryId) async {
    if (!AppConfig.useSupabase) return;
    final companyId = _currentCompanyId;
    if (companyId == null) return;

    try {
      final data = await Supabase.instance.client
          .from('inventory_items')
          .select()
          .eq('company_id', companyId)
          .eq('inventory_id', inventoryId)
          .eq('is_deleted', false)
          .order('updated_at', ascending: false);

      final box = _itemsBoxes[inventoryId];
      if (box == null) return;
      await box.clear();

      for (final itemData in data) {
        final item = _itemFromSupabaseRow(Map<String, dynamic>.from(itemData));
        item.supabaseId = itemData['id'] as String? ?? '';
        await box.add(item);
      }
    } catch (e) {
      debugPrint('⚠️ Item sync error: $e');
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

    final item = InventoryItem(
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
      productionDate: row['production_date'] != null ? DateTime.tryParse(row['production_date'] as String) : null,
      expireDate: row['expire_date'] != null ? DateTime.tryParse(row['expire_date'] as String) : null,
      createdAt: row['created_at'] != null ? DateTime.parse(row['created_at'] as String) : DateTime.now(),
      modified: row['updated_at'] != null ? DateTime.parse(row['updated_at'] as String) : DateTime.now(),
    );

    item.createdBy = row['created_by'] as String?;
    item.createdByName = row['created_by_name'] as String?;
    item.updatedBy = row['updated_by'] as String?;
    item.updatedByName = row['updated_by_name'] as String?;
    item.rowVersion = row['row_version'] as int? ?? 1;

    return item;
  }

  // ─── Label Accessors ───────────────────────────────────────────

  List<Label> get labels => _currentInventoryId != null ? (_labelsCache[_currentInventoryId!] ?? []) : [];
  List<String> get labelNames => labels.map((l) => l.name).toList();
  bool get hasLabels => labels.isNotEmpty;
  bool hasLabel(String name) => labels.any((l) => l.name == name);
  Label? getLabelByName(String name) {
    try { return labels.firstWhere((l) => l.name == name); } catch (_) { return null; }
  }
  Label? getLabelById(String id) {
    try { return labels.firstWhere((l) => l.id == id); } catch (_) { return null; }
  }
  Label? getLabelInfo(String name) => getLabelByName(name);

  List<Label> getSortedLabels({LabelSortType sortType = LabelSortType.nameAsc}) {
    final all = List<Label>.from(labels);
    switch (sortType) {
      case LabelSortType.nameAsc: all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case LabelSortType.nameDesc: all.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case LabelSortType.dateCreatedAsc: all.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case LabelSortType.dateCreatedDesc: all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case LabelSortType.dateModifiedAsc: all.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case LabelSortType.dateModifiedDesc: all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return all;
  }

  List<String> getSortedLabelNames({LabelSortType sortType = LabelSortType.nameAsc}) =>
      getSortedLabels(sortType: sortType).map((l) => l.name).toList();

  // ─── Label CRUD ─────────────────────────────────────────────────

  Future<Label> createLabel(String name) async {
    if (_currentInventoryId == null) throw Exception('No inventory selected');
    final companyId = _currentCompanyId;
    if (companyId == null) throw Exception('No company selected');

    final user = Supabase.instance.client.auth.currentUser;
    final now = DateTime.now();

    if (AppConfig.useSupabase) {
      final response = await Supabase.instance.client.from('labels').insert({
        'company_id': companyId,
        'inventory_id': _currentInventoryId,
        'name': name,
        'created_by': user?.id,
        'created_by_name': user?.userMetadata?['display_name'] ?? user?.email ?? 'Unknown',
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      }).select().single();

      final label = Label.fromSupabase(Map<String, dynamic>.from(response));
      _addLabelToCache(label);
      return label;
    }

    final label = Label.create(
      name: name, companyId: companyId, inventoryId: _currentInventoryId!,
      createdBy: 'offline', createdByName: 'Offline User',
    );
    _addLabelToCache(label);
    return label;
  }

  void _addLabelToCache(Label label) {
    final list = List<Label>.from(labels);
    final idx = list.indexWhere((l) => l.id == label.id);
    if (idx != -1) { list[idx] = label; } else { list.add(label); }
    _labelsCache[_currentInventoryId!] = list;
  }

  Future<void> renameLabel(String oldName, String newName) async {
    final label = getLabelByName(oldName);
    if (label == null) throw Exception('Label not found');

    if (AppConfig.useSupabase) {
      await Supabase.instance.client.from('labels').update({
        'name': newName, 'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', label.id);
    }

    final list = List<Label>.from(labels);
    final idx = list.indexWhere((l) => l.id == label.id);
    if (idx != -1) { list[idx] = label.copyWith(name: newName); _labelsCache[_currentInventoryId!] = list; }

    for (final item in getItemsByLabel(oldName)) {
      item.label = newName;
      await item.save();
    }
  }

  Future<void> deleteLabel(String name) async {
    final label = getLabelByName(name);
    if (label == null) return;

    if (AppConfig.useSupabase && _currentCompanyId != null) {
      await Supabase.instance.client.from('labels').update({
        'is_deleted': true, 'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', label.id);

      await Supabase.instance.client.from('inventory_items').update({
        'is_deleted': true,
      }).eq('company_id', _currentCompanyId!).eq('label', name);
    }

    final list = List<Label>.from(labels);
    list.removeWhere((l) => l.id == label.id);
    _labelsCache[_currentInventoryId!] = list;

    for (final item in getItemsByLabel(name)) {
      await item.delete();
    }
  }

  // ─── Item Management ───────────────────────────────────────────

  List<InventoryItem> getItemsByLabel(String label) {
    if (_currentInventoryId == null || !_itemsBoxes.containsKey(_currentInventoryId!)) return [];
    return _itemsBoxes[_currentInventoryId!]!.values.where((item) => item.label == label).toList();
  }

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
      'name': item.name, 'code': item.code, 'barcode': item.barcode,
      'color': item.color, 'material': item.material, 'size': item.size,
      'quantity': item.quantity, 'label': item.label, 'note': item.note,
      'custom_fields': item.customFields,
      'production_date': item.productionDate?.toIso8601String(),
      'expire_date': item.expireDate?.toIso8601String(),
      'created_by': user?.id,
      'created_by_name': user?.userMetadata?['display_name'] ?? user?.email ?? 'Unknown',
      'updated_at': now,
    };

    final supabaseId = item.supabaseId;
    final userName = user?.userMetadata?['display_name'] ?? user?.email ?? 'Unknown';

    if (supabaseId != null && supabaseId.isNotEmpty) {
      final result = await client.rpc('update_item_with_version_check', params: {
        'p_item_id': supabaseId,
        'p_data': data,
        'p_expected_version': item.rowVersion,
        'p_updated_by': user?.id,
        'p_updated_by_name': userName,
      });

      final resultMap = Map<String, dynamic>.from(result as Map);
      if (resultMap['success'] == true) {
        item.rowVersion = resultMap['new_version'] as int? ?? item.rowVersion + 1;
        item.updatedBy = user?.id;
        item.updatedByName = userName;
        await item.save();
      } else {
        debugPrint('⚠️ Optimistic lock conflict: ${resultMap['message']}');
        await _syncItemsFromSupabase(_currentInventoryId!);
        throw Exception(resultMap['message'] ?? 'Update conflict. Please refresh.');
      }
    } else {
      final newId = _uuid.v4();
      data['id'] = newId;
      data['created_at'] = item.createdAt.toUtc().toIso8601String();
      await client.from('inventory_items').insert(data);
      item.supabaseId = newId;
      item.createdBy = user?.id;
      item.createdByName = userName;
      item.rowVersion = 1;
      await item.save();
    }
  } catch (e) {
    debugPrint('❌ Sync error for ${item.name}: $e');
    rethrow;
  }
}

  Future<int> importItems(String label, List<InventoryItem> newItems) async {
    if (_currentInventoryId == null) return 0;
    final box = _itemsBoxes[_currentInventoryId!];
    if (box == null) return 0;

    int importedCount = 0;
    for (final newItem in newItems) {
      newItem.label = label;
      final isDuplicate = box.values.any((existing) =>
          existing.name == newItem.name && existing.code == newItem.code && existing.barcode == newItem.barcode);
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

  // ─── Search ────────────────────────────────────────────────────

  List<Map<String, dynamic>> searchAllInventories(String query) {
    final results = <Map<String, dynamic>>[];
    final lowerQuery = query.toLowerCase().trim();
    if (lowerQuery.isEmpty) return results;

    final inventoryNames = getAllInventoryNames();
    final allIds = <String>{..._itemsBoxes.keys, ...inventoryNames.keys};

    for (final inventoryId in allIds) {
      try {
        Box<InventoryItem>? box;
        if (_itemsBoxes.containsKey(inventoryId)) {
          box = _itemsBoxes[inventoryId];
        } else if (Hive.isBoxOpen('items_$inventoryId')) {
          box = Hive.box<InventoryItem>('items_$inventoryId');
        }
        if (box == null || box.isEmpty) continue;

        final invName = inventoryNames[inventoryId] ?? getInventoryName(inventoryId);
        for (final item in box.values) {
          if (item.matchesQuery(lowerQuery)) {
            results.add({'item': item, 'inventoryId': inventoryId, 'inventoryName': invName});
          }
        }
      } catch (_) {}
    }

    results.sort((a, b) {
      final aName = (a['item'] as InventoryItem).name.toLowerCase();
      final bName = (b['item'] as InventoryItem).name.toLowerCase();
      if (aName == lowerQuery) return -1;
      if (bName == lowerQuery) return 1;
      return aName.compareTo(bName);
    });
    return results;
  }

  // ─── Helpers ───────────────────────────────────────────────────

  Map<String, String> getAllInventoryNames() {
    final names = <String, String>{};
    try {
      final box = Hive.box('inventories_list');
      for (final key in box.keys) {
        final value = box.get(key);
        if (value is Map) {
          names[key.toString()] = Map<String, dynamic>.from(value)['name'] as String? ?? 'Unknown';
        }
      }
    } catch (_) {}
    return names;
  }

  String getInventoryName(String inventoryId) {
    try {
      final box = Hive.box('inventories_list');
      final value = box.get(inventoryId);
      if (value is Map) {
        return Map<String, dynamic>.from(value)['name'] as String? ?? inventoryId;
      }
    } catch (_) {}
    return inventoryId;
  }

  InventorySettings? get currentSettings {
    if (_currentInventoryId == null || !_settingsBoxes.containsKey(_currentInventoryId!)) return null;
    final settings = _settingsBoxes[_currentInventoryId!]!.get('main');
    if (settings == null) {
      final ds = InventorySettings();
      _settingsBoxes[_currentInventoryId!]!.put('main', ds);
      return ds;
    }
    return settings;
  }

  Future<void> updateSettings(InventorySettings settings) async {
    if (_currentInventoryId == null) return;
    await _settingsBoxes[_currentInventoryId!]!.put('main', settings);
  }

  Future<void> deleteInventoryData(String id) async {
    for (final box in [_itemsBoxes[id], _labelsBoxes[id], _settingsBoxes[id]]) {
      if (box != null) { try { await box.flush(); await box.close(); } catch (_) {} }
    }
    _itemsBoxes.remove(id); _labelsBoxes.remove(id); _settingsBoxes.remove(id); _labelsCache.remove(id);
    for (final suffix in ['items_', 'labels_', 'inventory_settings_']) {
      try { await Hive.deleteBoxFromDisk('$suffix$id'); } catch (_) {}
    }
    if (_currentInventoryId == id) _currentInventoryId = null;
  }

  Future<void> dispose() async {
    await _closeAllBoxes();
    _currentInventoryId = null;
    _currentCompanyId = null;
  }
}