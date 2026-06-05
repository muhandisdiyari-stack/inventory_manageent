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
  Future<void>? _initFuture;

  String? get currentInventoryId => _currentInventoryId;
  String? get currentCompanyId => _currentCompanyId;

  // ─── Initialization with Race Condition Fix ────────────────────

  Future<void> initializeForInventory(String inventoryId) {
    if (_initFuture != null && _currentInventoryId == inventoryId) return _initFuture!;
    _initFuture = _doInitialize(inventoryId).whenComplete(() => _initFuture = null);
    return _initFuture!;
  }

  Future<void> _doInitialize(String inventoryId) async {
    try {
      await _loadCompanyId();
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
      if (AppConfig.useSupabase && _currentCompanyId != null) {
        await syncLabelsFromSupabase(inventoryId);
        await _syncItemsFromSupabase(inventoryId);
      } else {
        _loadLabelsFromCache(inventoryId);
      }
    } catch (e) {
      debugPrint('❌ Error initializing inventory $inventoryId: $e');
      _loadLabelsFromCache(inventoryId);
      rethrow;
    }
  }

  Future<void> _closeAllBoxes() async {
    for (final box in [..._itemsBoxes.values, ..._labelsBoxes.values, ..._settingsBoxes.values]) {
      try { await box.flush(); await box.close(); } catch (_) {}
    }
    _itemsBoxes.clear(); _labelsBoxes.clear(); _settingsBoxes.clear(); _labelsCache.clear();
  }

  Future<String?> getCurrentCompanyId() async {
    if (_currentCompanyId != null) return _currentCompanyId;
    await _loadCompanyId();
    return _currentCompanyId;
  }

  Future<void> setCurrentCompany(String companyId) async {
    if (_currentCompanyId != companyId) {
      _currentCompanyId = companyId;
      if (_currentInventoryId != null) {
        try { await initializeForInventory(_currentInventoryId!); } catch (e) { debugPrint('⚠️ Reinit error: $e'); }
      }
    }
  }

  Future<void> _loadCompanyId() async {
    if (!AppConfig.useSupabase || _currentCompanyId != null) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final data = await Supabase.instance.client.from('inventory_members')
          .select('inventories!inner(company_id)').eq('user_id', user.id).limit(1).maybeSingle();
      if (data != null) { final inv = data['inventories'] as Map?; if (inv != null) { _currentCompanyId = inv['company_id']?.toString(); return; } }
      final profile = await Supabase.instance.client.from('profiles').select('company_id').eq('id', user.id).maybeSingle();
      _currentCompanyId = profile?['company_id']?.toString();
    } catch (e) { debugPrint('⚠️ Load company ID error: $e'); _currentCompanyId = null; }
  }

  // ─── Label Sync ─────────────────────────────────────────────────

  Future<void> syncLabelsFromSupabase(String inventoryId) async {
    if (!AppConfig.useSupabase) return;
    final companyId = _currentCompanyId; if (companyId == null) return;
    try {
      final data = await Supabase.instance.client.from('labels').select()
          .eq('company_id', companyId).eq('inventory_id', inventoryId).eq('is_deleted', false).order('name');
      final seenNames = <String>{}; final labels = <Label>[];
      for (final row in data) {
        try { final label = Label.fromSupabase(Map<String, dynamic>.from(row)); if (!seenNames.contains(label.name)) { seenNames.add(label.name); labels.add(label); } }
        catch (e) { debugPrint('⚠️ Parse label error: $e'); }
      }
      final box = _labelsBoxes[inventoryId];
      if (box != null) {
        await box.put('labels_cache', labels.map((l) => l.toSupabaseJson()).toList());
        await box.put('label_names', labels.map((l) => l.name).toList());
      }
      _labelsCache[inventoryId] = labels;
    } catch (e) { debugPrint('⚠️ Label sync error: $e'); _loadLabelsFromCache(inventoryId); }
  }

  void _loadLabelsFromCache(String inventoryId) {
    final box = _labelsBoxes[inventoryId];
    if (box == null) { _labelsCache[inventoryId] = []; return; }
    final raw = box.get('labels_cache');
    _labelsCache[inventoryId] = (raw is List && raw.isNotEmpty)
        ? raw.map((e) => Label.fromSupabase(Map<String, dynamic>.from(e))).toList() : [];
  }

  // ─── Item Sync ──────────────────────────────────────────────────

  Future<void> _syncItemsFromSupabase(String inventoryId) async {
    if (!AppConfig.useSupabase) return;
    final companyId = _currentCompanyId; if (companyId == null) return;
    try {
      final data = await Supabase.instance.client.from('inventory_items')
          .select('*, labels(name)').eq('company_id', companyId).eq('inventory_id', inventoryId)
          .eq('is_deleted', false).order('updated_at', ascending: false);
      final box = _itemsBoxes[inventoryId]; if (box == null) return;
      int updated = 0, added = 0;
      for (final itemData in data) {
        try {
          final item = _itemFromSupabaseRow(Map<String, dynamic>.from(itemData));
          bool found = false;
          for (final existingItem in box.values) {
            if (existingItem.supabaseId == item.supabaseId) {
              _updateItemFields(existingItem, item); await existingItem.save(); found = true; updated++; break;
            }
          }
          if (!found) { await box.add(item); added++; }
        } catch (e) { debugPrint('⚠️ Sync item error: $e'); }
      }
    } catch (e) { debugPrint('⚠️ Item sync error: $e'); }
  }

  Future<void> syncItemsFromRealtime(String inventoryId) async {
    if (!AppConfig.useSupabase) return;
    final box = _itemsBoxes[inventoryId];
    if (box == null) return;
    try {
      final data = await Supabase.instance.client
          .from('inventory_items')
          .select()
          .eq('inventory_id', inventoryId)
          .eq('is_deleted', false)
          .order('updated_at', ascending: false)
          .limit(100);
      
      // Clear existing items in cache
      await box.clear();
      
      // Re-add only non-deleted items from Supabase
      for (final itemData in data) {
        final item = _itemFromSupabaseRow(Map<String, dynamic>.from(itemData));
        await box.add(item);
      }
    } catch (e) {
      debugPrint('⚠️ Realtime sync error: $e');
    }
  }

  void _updateItemFields(InventoryItem target, InventoryItem source) {
    target.name = source.name; target.code = source.code; target.barcode = source.barcode;
    target.quantity = source.quantity; target.label = source.label; target.note = source.note;
    target.color = source.color; target.material = source.material; target.size = source.size;
    target.customFields = source.customFields; target.productionDate = source.productionDate;
    target.expireDate = source.expireDate; target.modified = source.modified;
    target.rowVersion = source.rowVersion; target.labelId = source.labelId; target.isSynced = true;
  }

  InventoryItem _itemFromSupabaseRow(Map<String, dynamic> row) {
    final customFields = <String, String>{};
    final rawCustom = row['custom_fields'];
    if (rawCustom is Map) { for (final entry in rawCustom.entries) { customFields[entry.key.toString()] = entry.value.toString(); } }
    final supabaseId = row['id'] as String? ?? '';
    final labelName = row['labels'] is Map ? (row['labels'] as Map)['name']?.toString() ?? '' : (row['label'] as String?) ?? '';
    final item = InventoryItem(
      id: supabaseId.isNotEmpty ? supabaseId : _uuid.v4(), name: row['name'] as String? ?? '',
      code: row['code'] as String? ?? '', barcode: row['barcode'] as String? ?? '',
      color: row['color'] as String? ?? '', material: row['material'] as String? ?? '',
      size: row['size'] as String? ?? '', quantity: row['quantity'] as int? ?? 0, label: labelName,
      note: row['note'] as String? ?? '', customFields: customFields,
      productionDate: row['production_date'] != null ? DateTime.tryParse(row['production_date'] as String) : null,
      expireDate: row['expire_date'] != null ? DateTime.tryParse(row['expire_date'] as String) : null,
      createdAt: row['created_at'] != null ? DateTime.parse(row['created_at'] as String) : DateTime.now(),
      modified: row['updated_at'] != null ? DateTime.parse(row['updated_at'] as String) : DateTime.now(),
    );
    item.supabaseId = supabaseId; item.createdBy = row['created_by'] as String?;
    item.createdByName = row['created_by_name'] as String?; item.updatedBy = row['updated_by'] as String?;
    item.updatedByName = row['updated_by_name'] as String?; item.rowVersion = row['row_version'] as int? ?? 1;
    item.companyId = row['company_id'] as String?; item.inventoryId = row['inventory_id'] as String?;
    item.labelId = row['label_id'] as String?; item.isSynced = true;
    return item;
  }

  // ─── Label Accessors ───────────────────────────────────────────

  List<Label> get labels => _currentInventoryId != null ? (_labelsCache[_currentInventoryId!] ?? []) : [];
  List<String> get labelNames => labels.map((l) => l.name).toList();
  bool get hasLabels => labels.isNotEmpty;
  bool hasLabel(String name) => labels.any((l) => l.name == name);
  Label? getLabelByName(String name) { try { return labels.firstWhere((l) => l.name == name); } catch (_) { return null; } }

  List<String> getSortedLabelNames({LabelSortType sortType = LabelSortType.nameAsc}) {
    final all = List<Label>.from(labels);
    switch (sortType) {
      case LabelSortType.nameAsc: all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case LabelSortType.nameDesc: all.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case LabelSortType.dateCreatedAsc: all.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case LabelSortType.dateCreatedDesc: all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case LabelSortType.dateModifiedAsc: all.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case LabelSortType.dateModifiedDesc: all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return all.map((l) => l.name).toList();
  }

  // ─── Label CRUD ─────────────────────────────────────────────────

  Future<Label> createLabel(String name) async {
    if (_currentInventoryId == null) throw Exception('No inventory selected');
    if (_currentCompanyId == null) throw Exception('No company selected');
    final user = Supabase.instance.client.auth.currentUser; final now = DateTime.now();
    if (AppConfig.useSupabase) {
      try {
        final response = await Supabase.instance.client.from('labels').insert({
          'company_id': _currentCompanyId, 'inventory_id': _currentInventoryId!, 'name': name,
          'created_by': user?.id, 'created_by_name': user?.userMetadata?['display_name'] ?? user?.email ?? 'Unknown',
          'created_at': now.toUtc().toIso8601String(), 'updated_at': now.toUtc().toIso8601String(),
        }).select().single();
        final label = Label.fromSupabase(Map<String, dynamic>.from(response)); _addLabelToCache(label); return label;
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          final existing = await Supabase.instance.client.from('labels').select()
              .eq('company_id', _currentCompanyId as Object).eq('inventory_id', _currentInventoryId!)
              .eq('name', name).eq('is_deleted', false).maybeSingle();
          if (existing != null) { final label = Label.fromSupabase(Map<String, dynamic>.from(existing)); _addLabelToCache(label); return label; }
        }
        rethrow;
      }
    }
    final label = Label.create(name: name, companyId: _currentCompanyId!, inventoryId: _currentInventoryId!, createdBy: 'offline', createdByName: 'Offline User');
    _addLabelToCache(label); return label;
  }

  void _addLabelToCache(Label label) {
    final list = List<Label>.from(labels);
    final idx = list.indexWhere((l) => l.id == label.id);
    if (idx != -1) { list[idx] = label; } else { list.add(label); }
    _labelsCache[_currentInventoryId!] = list;
  }

  Future<void> renameLabel(String oldName, String newName) async {
    final label = getLabelByName(oldName); if (label == null) throw Exception('Label not found');
    if (AppConfig.useSupabase) {
      await Supabase.instance.client.from('labels').update({'name': newName, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', label.id);
    }
    final list = List<Label>.from(labels); final idx = list.indexWhere((l) => l.id == label.id);
    if (idx != -1) { list[idx] = label.copyWith(name: newName); _labelsCache[_currentInventoryId!] = list; }
    for (final item in getItemsByLabel(oldName)) { item.label = newName; await item.save(); }
  }

  Future<void> deleteLabel(String name) async {
    final label = getLabelByName(name); if (label == null) return;
    if (AppConfig.useSupabase && _currentCompanyId != null) {
      await Supabase.instance.client.from('labels').update({'is_deleted': true, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', label.id);
    }
    final list = List<Label>.from(labels); list.removeWhere((l) => l.id == label.id); _labelsCache[_currentInventoryId!] = list;
    final box = _itemsBoxes[_currentInventoryId!];
    if (box != null) { for (final item in box.values.where((i) => i.label == name).toList()) { await item.delete(); } }
  }

  // ─── Item Management ───────────────────────────────────────────

  List<InventoryItem> getItemsByLabel(String label) {
    if (_currentInventoryId == null || !_itemsBoxes.containsKey(_currentInventoryId!)) return [];
    return _itemsBoxes[_currentInventoryId!]!.values.where((item) => item.label == label).toList();
  }

  Future<void> saveItem(InventoryItem item) async {
    if (_currentInventoryId == null) return;
    final box = _itemsBoxes[_currentInventoryId!]; if (box == null) return;
    item.inventoryId = _currentInventoryId; item.companyId = _currentCompanyId; item.isSynced = false;
    if (item.labelId == null && item.label.isNotEmpty) { final label = getLabelByName(item.label); if (label != null) item.labelId = label.id; }
    if (item.key != null) { await item.save(); } else { await box.add(item); }
    await _syncItemToSupabase(item);
    item.isSynced = true; if (item.key != null) await item.save();
  }

  Future<void> deleteItem(InventoryItem item) async {
    // Remove from local Hive immediately
    await item.delete();

    // Soft delete in Supabase
    if (AppConfig.useSupabase && item.supabaseId != null && item.supabaseId!.isNotEmpty) {
      await Supabase.instance.client.from('inventory_items').update({
        'is_deleted': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', item.supabaseId!);
    }
  }

  Future<void> _syncItemToSupabase(InventoryItem item) async {
    if (!AppConfig.useSupabase) return;
    final companyId = _currentCompanyId;
    final inventoryId = _currentInventoryId;
    if (companyId == null || inventoryId == null) return;

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      final now = DateTime.now().toUtc().toIso8601String();
      final userName = user?.userMetadata?['display_name'] ?? user?.email ?? 'Unknown';

      final data = <String, dynamic>{
        'company_id': companyId,
        'inventory_id': inventoryId,
        'name': item.name,
        'code': item.code,
        'barcode': item.barcode,
        'color': item.color,
        'material': item.material,
        'size': item.size,
        'quantity': item.quantity,
        'label': item.label,
        'note': item.note,
        'label_id': item.labelId,
        'custom_fields': item.userCustomFields,
        'production_date': item.productionDate?.toIso8601String(),
        'expire_date': item.expireDate?.toIso8601String(),
        'updated_at': now,
      };

      final supabaseId = item.supabaseId;

      if (supabaseId != null && supabaseId.isNotEmpty) {
        // UPDATE existing item
        data['updated_by'] = user?.id;
        data['updated_by_name'] = userName;
        final response = await client.from('inventory_items').update(data).eq('id', supabaseId).select();
        debugPrint('✅ Item updated in Supabase: ${item.name}');
      } else {
        // INSERT new item
        data['id'] = item.id;
        data['created_at'] = item.createdAt.toUtc().toIso8601String();
        data['created_by'] = user?.id;
        data['created_by_name'] = userName;
        data['row_version'] = 1;
        final response = await client.from('inventory_items').insert(data).select();
        if (response.isNotEmpty) {
          item.supabaseId = response.first['id']?.toString() ?? item.id;
          item.createdBy = user?.id;
          item.createdByName = userName;
          debugPrint('✅ Item inserted to Supabase: ${item.name}');
        }
      }
    } catch (e) {
      debugPrint('❌ Sync error for ${item.name}: $e');
    }
  }

  Future<int> importItems(String label, List<InventoryItem> newItems) async {
    if (_currentInventoryId == null) return 0;
    final box = _itemsBoxes[_currentInventoryId!]; if (box == null) return 0;
    final labelObj = getLabelByName(label); int importedCount = 0;
    for (final newItem in newItems) {
      newItem.label = label; newItem.labelId = labelObj?.id;
      newItem.companyId = _currentCompanyId; newItem.inventoryId = _currentInventoryId;
      if (!box.values.any((e) => e.name == newItem.name && e.code == newItem.code && e.barcode == newItem.barcode)) {
        newItem.isSynced = false; await box.add(newItem);
        try { await _syncItemToSupabase(newItem); newItem.isSynced = true; await newItem.save(); } catch (_) { debugPrint('⚠️ Import sync failed for ${newItem.name}'); }
        importedCount++;
      }
    }
    return importedCount;
  }

  Map<String, List<InventoryItem>> getAllItems() {
    final allItems = <String, List<InventoryItem>>{};
    if (_currentInventoryId == null) return allItems;
    for (final label in labelNames) { allItems[label] = getItemsByLabel(label); }
    return allItems;
  }

  List<Map<String, dynamic>> searchAllInventories(String query) {
    final results = <Map<String, dynamic>>[]; final lowerQuery = query.toLowerCase().trim();
    if (lowerQuery.isEmpty) return results;
    final inventoryNames = getAllInventoryNames();
    for (final inventoryId in {..._itemsBoxes.keys, ...inventoryNames.keys}) {
      try {
        Box<InventoryItem>? box;
        if (_itemsBoxes.containsKey(inventoryId)) { box = _itemsBoxes[inventoryId]; }
        else if (Hive.isBoxOpen('items_$inventoryId')) { box = Hive.box<InventoryItem>('items_$inventoryId'); }
        if (box == null || box.isEmpty) continue;
        for (final item in box.values) {
          if (item.matchesQuery(lowerQuery)) results.add({'item': item, 'inventoryId': inventoryId, 'inventoryName': inventoryNames[inventoryId] ?? getInventoryName(inventoryId)});
        }
      } catch (_) {}
    }
    results.sort((a, b) => (a['item'] as InventoryItem).name.toLowerCase().compareTo((b['item'] as InventoryItem).name.toLowerCase()));
    return results;
  }

  Map<String, String> getAllInventoryNames() {
    final names = <String, String>{};
    try { final box = Hive.box('inventories_list'); final d = box.get('cached_inventories'); if (d is List) { for (final i in d) { if (i is Map) names[i['id']?.toString() ?? ''] = i['name']?.toString() ?? 'Unknown'; } } } catch (_) {}
    return names;
  }

  String getInventoryName(String inventoryId) {
    try { final box = Hive.box('inventories_list'); final d = box.get('cached_inventories'); if (d is List) { for (final i in d) { if (i is Map && i['id']?.toString() == inventoryId) return i['name']?.toString() ?? inventoryId; } } } catch (_) {}
    return inventoryId;
  }

  InventorySettings? get currentSettings {
    if (_currentInventoryId == null || !_settingsBoxes.containsKey(_currentInventoryId!)) return null;
    final s = _settingsBoxes[_currentInventoryId!]!.get('main');
    if (s == null) { final ds = InventorySettings(); _settingsBoxes[_currentInventoryId!]!.put('main', ds); return ds; }
    return s;
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
    for (final suffix in ['items_', 'labels_', 'inventory_settings_']) { try { await Hive.deleteBoxFromDisk('$suffix$id'); } catch (_) {} }
    if (_currentInventoryId == id) _currentInventoryId = null;
  }

  Future<void> dispose() async { await _closeAllBoxes(); _currentInventoryId = null; _currentCompanyId = null; }
}