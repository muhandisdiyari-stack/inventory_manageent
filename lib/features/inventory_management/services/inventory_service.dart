import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';
import '../../../core/config/app_config.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// ─── Label Info Model ─────────────────────────────────────────────

class LabelInfo {
  final String name;
  final String? supabaseId;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final bool isSynced;

  LabelInfo({
    required this.name,
    this.supabaseId,
    required this.createdAt,
    DateTime? modifiedAt,
    this.isSynced = false,
  }) : modifiedAt = modifiedAt ?? createdAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'supabaseId': supabaseId,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'isSynced': isSynced,
      };

  factory LabelInfo.fromJson(Map<String, dynamic> json) => LabelInfo(
        name: json['name'] as String,
        supabaseId: json['supabaseId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: json['modifiedAt'] != null
            ? DateTime.parse(json['modifiedAt'] as String)
            : null,
        isSynced: json['isSynced'] as bool? ?? false,
      );

  LabelInfo copyWith({
    String? name,
    String? supabaseId,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isSynced,
  }) {
    return LabelInfo(
      name: name ?? this.name,
      supabaseId: supabaseId ?? this.supabaseId,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

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

class InventoryService {
  final Map<String, Box<InventoryItem>> _itemsBoxes = {};
  final Map<String, Box> _labelsBoxes = {};
  final Map<String, Box<InventorySettings>> _settingsBoxes = {};

  // Cache for parsed label infos
  final Map<String, Map<String, LabelInfo>> _labelInfosCache = {};

  String? _currentInventoryId;
  String? _currentCompanyId;
  DateTime? _lastSyncTimestamp;
  bool _isInitializing = false;

  String? get currentInventoryId => _currentInventoryId;
  String? get currentCompanyId => _currentCompanyId;
  bool get isInitializing => _isInitializing;

  // ─── Box Availability Checks ────────────────────────────────────

  bool _isBoxAvailable(String boxType, String? inventoryId) {
    if (inventoryId == null) return false;
    switch (boxType) {
      case 'labels':
        return _labelsBoxes.containsKey(inventoryId) &&
            _labelsBoxes[inventoryId]!.isOpen;
      case 'items':
        return _itemsBoxes.containsKey(inventoryId) &&
            _itemsBoxes[inventoryId]!.isOpen;
      case 'settings':
        return _settingsBoxes.containsKey(inventoryId) &&
            _settingsBoxes[inventoryId]!.isOpen;
      default:
        return false;
    }
  }

  // ─── Initialization ─────────────────────────────────────────────

  Future<void> initializeForInventory(String inventoryId) async {
    if (_isInitializing && _currentInventoryId == inventoryId) return;

    _isInitializing = true;

    try {
      // Flush and close all previously open boxes
      await _closeAllBoxes();

      // Open labels box
      final String labelsBoxName = 'labels_$inventoryId';
      final labelsBox = await Hive.openBox(labelsBoxName);
      if (!labelsBox.containsKey('labels')) {
        await labelsBox.put('labels', <String>[]);
      }
      if (!labelsBox.containsKey('labelInfos')) {
        await labelsBox.put('labelInfos', <String, Map<String, dynamic>>{});
      }
      _labelsBoxes[inventoryId] = labelsBox;

      // Open items box
      final String itemsBoxName = 'items_$inventoryId';
      final itemsBox = await Hive.openBox<InventoryItem>(itemsBoxName);
      _itemsBoxes[inventoryId] = itemsBox;

      // Open settings box
      final String settingsBoxName = 'inventory_settings_$inventoryId';
      final settingsBox = await Hive.openBox<InventorySettings>(settingsBoxName);
      if (!settingsBox.containsKey('main')) {
        await settingsBox.put('main', InventorySettings());
      }
      _settingsBoxes[inventoryId] = settingsBox;

      _currentInventoryId = inventoryId;

      // Invalidate label infos cache for this inventory
      _labelInfosCache.remove(inventoryId);

      // Load company ID for sync
      await _loadCompanyId();

      // Sync with Supabase if enabled and company ID is available
      if (AppConfig.useSupabase && _currentCompanyId != null) {
        debugPrint('🔄 Syncing inventory $inventoryId for company $_currentCompanyId');
        await _syncLabelsWithSupabase(inventoryId);
        await _loadAndMergeSupabaseItems(inventoryId);
      } else {
        debugPrint('⚠️ Skipping sync - no company ID or Supabase disabled');
      }
    } catch (e) {
      debugPrint('Error initializing inventory $inventoryId: $e');
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _closeAllBoxes() async {
    for (final box in _itemsBoxes.values) {
      try {
        await box.flush();
        await box.close();
      } catch (_) {}
    }
    for (final box in _labelsBoxes.values) {
      try {
        await box.flush();
        await box.close();
      } catch (_) {}
    }
    for (final box in _settingsBoxes.values) {
      try {
        await box.flush();
        await box.close();
      } catch (_) {}
    }
    _itemsBoxes.clear();
    _labelsBoxes.clear();
    _settingsBoxes.clear();
    _labelInfosCache.clear();
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
      debugPrint('Could not load company ID: $e');
      _currentCompanyId = null;
    }
  }

  void selectInventory(String id) {
    _currentInventoryId = id;
  }

  // ─── Inventory Deletion ─────────────────────────────────────────

  Future<void> deleteInventoryData(String id) async {
    debugPrint('=== Deleting inventory data for: $id ===');

    try {
      if (_itemsBoxes.containsKey(id)) {
        try {
          await _itemsBoxes[id]!.flush();
          await _itemsBoxes[id]!.close();
        } catch (_) {}
        _itemsBoxes.remove(id);
      }
      if (_labelsBoxes.containsKey(id)) {
        try {
          await _labelsBoxes[id]!.flush();
          await _labelsBoxes[id]!.close();
        } catch (_) {}
        _labelsBoxes.remove(id);
      }
      if (_settingsBoxes.containsKey(id)) {
        try {
          await _settingsBoxes[id]!.flush();
          await _settingsBoxes[id]!.close();
        } catch (_) {}
        _settingsBoxes.remove(id);
      }

      _labelInfosCache.remove(id);

      await _deleteBoxSafely('items_$id');
      await _deleteBoxSafely('labels_$id');
      await _deleteBoxSafely('inventory_settings_$id');

      if (_currentInventoryId == id) {
        _currentInventoryId = null;
      }

      final companyId = _currentCompanyId;
      if (AppConfig.useSupabase && companyId != null) {
        try {
          await Supabase.instance.client
              .from('inventory_items')
              .delete()
              .eq('inventory_id', id)
              .eq('company_id', companyId);
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

  // ─── Supabase Label Sync ───────────────────────────────────────

  Future<void> _syncLabelsWithSupabase(String inventoryId) async {
    if (!AppConfig.useSupabase) return;
    final companyId = _currentCompanyId;
    if (companyId == null) return;
    if (!_labelsBoxes.containsKey(inventoryId)) return;

    try {
      final client = Supabase.instance.client;

      // Load labels from Supabase (is_deleted column now exists)
      final supabaseLabels = await client
          .from('labels')
          .select()
          .eq('company_id', companyId)
          .eq('is_deleted', false);

      final localInfos = Map<String, dynamic>.from(
        _labelsBoxes[inventoryId]!.get('labelInfos',
            defaultValue: <String, Map<String, dynamic>>{}) as Map,
      );

      bool hasChanges = false;

      for (final sl in supabaseLabels) {
        final name = sl['name'] as String;
        if (!localInfos.containsKey(name)) {
          localInfos[name] = LabelInfo(
            name: name,
            supabaseId: sl['id'] as String?,
            createdAt: sl['created_at'] != null
                ? DateTime.parse(sl['created_at'] as String)
                : DateTime.now(),
            modifiedAt: sl['updated_at'] != null
                ? DateTime.parse(sl['updated_at'] as String)
                : null,
            isSynced: true,
          ).toJson();
          hasChanges = true;
        }
      }

      if (hasChanges) {
        final currentLabels = List<String>.from(
          _labelsBoxes[inventoryId]!.get('labels', defaultValue: <String>[]) as List,
        );

        for (final name in localInfos.keys) {
          if (!currentLabels.contains(name)) {
            currentLabels.add(name);
          }
        }

        await _labelsBoxes[inventoryId]!.put('labels', currentLabels);
        await _labelsBoxes[inventoryId]!.put('labelInfos', localInfos);
        _labelInfosCache.remove(inventoryId);
        debugPrint('✅ Synced ${supabaseLabels.length} labels from Supabase');
      }
    } catch (e) {
      debugPrint('Label sync error: $e');
    }
  }

  // ─── Supabase Item Sync ────────────────────────────────────────

  Future<void> _syncItemToSupabase(InventoryItem item) async {
    if (!AppConfig.useSupabase) return;
    if (_currentInventoryId == null) return;
    final companyId = _currentCompanyId;
    if (companyId == null) return;

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

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
        'created_by': user.id,
        'created_by_name': user.userMetadata?['display_name'] ?? user.email ?? 'Unknown',
        'updated_at': now,
      };

      final supabaseId = item.customFields['_supabase_id'];

      if (supabaseId != null && supabaseId.isNotEmpty) {
        data['id'] = supabaseId;
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

  Future<void> _loadAndMergeSupabaseItems(String inventoryId) async {
    if (!AppConfig.useSupabase) return;
    final companyId = _currentCompanyId;
    if (companyId == null) return;

    try {
      final client = Supabase.instance.client;

      final supabaseItems = await client
          .from('inventory_items')
          .select()
          .eq('company_id', companyId)
          .eq('inventory_id', inventoryId)
          .eq('is_deleted', false)
          .order('updated_at', ascending: false);

      final box = _itemsBoxes[inventoryId];
      if (box == null) return;

      int updatedCount = 0;
      int addedCount = 0;

      for (final itemData in supabaseItems) {
        final supabaseId = itemData['id'] as String?;
        if (supabaseId == null) continue;

        InventoryItem? existingItem;
        for (final item in box.values) {
          if (item.customFields['_supabase_id'] == supabaseId) {
            existingItem = item;
            break;
          }
        }

        if (existingItem != null) {
          final supabaseUpdated = itemData['updated_at'] != null
              ? DateTime.parse(itemData['updated_at'] as String)
              : DateTime.now();

          if (supabaseUpdated.isAfter(existingItem.modified)) {
            existingItem.name = itemData['name'] as String? ?? existingItem.name;
            existingItem.code = itemData['code'] as String? ?? existingItem.code;
            existingItem.barcode = itemData['barcode'] as String? ?? existingItem.barcode;
            existingItem.color = itemData['color'] as String? ?? existingItem.color;
            existingItem.material = itemData['material'] as String? ?? existingItem.material;
            existingItem.size = itemData['size'] as String? ?? existingItem.size;
            existingItem.quantity = itemData['quantity'] as int? ?? existingItem.quantity;
            existingItem.label = itemData['label'] as String? ?? existingItem.label;
            existingItem.note = itemData['note'] as String? ?? existingItem.note;

            final supabaseCustomFields = itemData['custom_fields'] as Map<String, dynamic>?;
            if (supabaseCustomFields != null) {
              for (final entry in supabaseCustomFields.entries) {
                existingItem.customFields[entry.key] = entry.value.toString();
              }
            }
            existingItem.customFields['_supabase_id'] = supabaseId;

            existingItem.productionDate = itemData['production_date'] != null
                ? DateTime.parse(itemData['production_date'] as String)
                : existingItem.productionDate;
            existingItem.expireDate = itemData['expire_date'] != null
                ? DateTime.parse(itemData['expire_date'] as String)
                : existingItem.expireDate;
            existingItem.modified = supabaseUpdated;
            await existingItem.save();
            updatedCount++;
          }
        } else {
          final customFields = <String, String>{'_supabase_id': supabaseId};
          final supabaseCustomFields = itemData['custom_fields'] as Map<String, dynamic>?;
          if (supabaseCustomFields != null) {
            for (final entry in supabaseCustomFields.entries) {
              customFields[entry.key] = entry.value.toString();
            }
          }

          final newItem = InventoryItem(
            name: itemData['name'] as String? ?? '',
            code: itemData['code'] as String? ?? '',
            barcode: itemData['barcode'] as String? ?? '',
            color: itemData['color'] as String? ?? '',
            material: itemData['material'] as String? ?? '',
            size: itemData['size'] as String? ?? '',
            quantity: itemData['quantity'] as int? ?? 0,
            label: itemData['label'] as String? ?? '',
            note: itemData['note'] as String? ?? '',
            customFields: customFields,
            productionDate: itemData['production_date'] != null
                ? DateTime.parse(itemData['production_date'] as String)
                : null,
            expireDate: itemData['expire_date'] != null
                ? DateTime.parse(itemData['expire_date'] as String)
                : null,
            createdAt: itemData['created_at'] != null
                ? DateTime.parse(itemData['created_at'] as String)
                : DateTime.now(),
          );
          await box.add(newItem);
          addedCount++;
        }
      }

      _lastSyncTimestamp = DateTime.now();
      debugPrint('✅ Synced ${supabaseItems.length} items ($updatedCount updated, $addedCount added)');
    } catch (e) {
      debugPrint('❌ Load from Supabase error: $e');
    }
  }

  // ─── Label Management ──────────────────────────────────────────

  Map<String, LabelInfo> _parseLabelInfos(String inventoryId) {
    final rawMap = _labelsBoxes[inventoryId]!.get('labelInfos');
    if (rawMap is! Map) return {};

    return rawMap.map((key, value) {
      if (value is Map) {
        return MapEntry(
          key.toString(),
          LabelInfo.fromJson(Map<String, dynamic>.from(value)),
        );
      }
      return MapEntry(
        key.toString(),
        LabelInfo(name: key.toString(), createdAt: DateTime.now()),
      );
    });
  }

  Map<String, LabelInfo> get labelInfos {
    if (_currentInventoryId == null || !_isBoxAvailable('labels', _currentInventoryId)) {
      return {};
    }
    return _labelInfosCache[_currentInventoryId!] ??= _parseLabelInfos(_currentInventoryId!);
  }

  Future<void> _saveLabelInfos(String inventoryId, Map<String, dynamic> infos) async {
    await _labelsBoxes[inventoryId]!.put('labelInfos', infos);
    _labelInfosCache.remove(inventoryId);
  }

  List<String> get labels => getSortedLabels();

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
      case LabelSortType.nameDesc:
        sortedEntries.sort((a, b) => b.key.toLowerCase().compareTo(a.key.toLowerCase()));
      case LabelSortType.dateCreatedAsc:
        sortedEntries.sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
      case LabelSortType.dateCreatedDesc:
        sortedEntries.sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));
      case LabelSortType.dateModifiedAsc:
        sortedEntries.sort((a, b) => a.value.modifiedAt.compareTo(b.value.modifiedAt));
      case LabelSortType.dateModifiedDesc:
        sortedEntries.sort((a, b) => b.value.modifiedAt.compareTo(a.value.modifiedAt));
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
        _labelsBoxes[_currentInventoryId!]!.get('labelInfos',
            defaultValue: <String, Map<String, dynamic>>{}) as Map,
      );
      infos[label] = LabelInfo(
        name: label,
        createdAt: now,
        modifiedAt: now,
        isSynced: false,
      ).toJson();

      await _saveLabelInfos(_currentInventoryId!, infos);

      // Sync to Supabase
      final companyId = _currentCompanyId;
      if (AppConfig.useSupabase && companyId != null) {
        try {
          final client = Supabase.instance.client;
          final result = await client.from('labels').insert({
            'company_id': companyId,
            'name': label,
          }).select().single();

          final updatedInfos = Map<String, dynamic>.from(
            _labelsBoxes[_currentInventoryId!]!.get('labelInfos',
                defaultValue: <String, Map<String, dynamic>>{}) as Map,
          );
          final existingInfo = updatedInfos[label] as Map<String, dynamic>?;
          if (existingInfo != null) {
            final info = LabelInfo.fromJson(Map<String, dynamic>.from(existingInfo));
            updatedInfos[label] = info.copyWith(
              supabaseId: result['id'] as String?,
              modifiedAt: DateTime.now(),
              isSynced: true,
            ).toJson();
            await _saveLabelInfos(_currentInventoryId!, updatedInfos);
          }
        } catch (e) {
          debugPrint('Label sync error: $e');
        }
      }

      await ActivityLogService().addLog(ActivityLogEntry(
        id: _uuid.v4(),
        timestamp: now,
        action: 'created',
        entityType: 'label',
        entityName: label,
        inventoryId: _currentInventoryId,
        inventoryName: getInventoryName(_currentInventoryId!),
        details: 'Label created: "$label"',
      ));
    }
  }

  Future<void> renameLabel(String oldLabel, String newLabel) async {
    if (_currentInventoryId == null) return;

    if (!_labelsBoxes.containsKey(_currentInventoryId!)) {
      await initializeForInventory(_currentInventoryId!);
    }

    final supabaseId = getLabelInfo(oldLabel)?.supabaseId;
    final currentLabels = _getCurrentLabelsList();
    final index = currentLabels.indexOf(oldLabel);

    if (index != -1) {
      currentLabels[index] = newLabel;
      await _labelsBoxes[_currentInventoryId!]!.put('labels', currentLabels);

      final infos = Map<String, dynamic>.from(
        _labelsBoxes[_currentInventoryId!]!.get('labelInfos',
            defaultValue: <String, Map<String, dynamic>>{}) as Map,
      );
      final oldInfo = infos[oldLabel];
      if (oldInfo is Map) {
        final labelInfo = LabelInfo.fromJson(Map<String, dynamic>.from(oldInfo));
        infos.remove(oldLabel);
        infos[newLabel] = labelInfo.copyWith(
          name: newLabel,
          modifiedAt: DateTime.now(),
          isSynced: false,
        ).toJson();
        await _saveLabelInfos(_currentInventoryId!, infos);
      }

      final items = getItemsByLabel(oldLabel);
      for (var item in items) {
        item.label = newLabel;
        await item.save();
        await _syncItemToSupabase(item);
      }

      final companyId = _currentCompanyId;
      if (AppConfig.useSupabase && companyId != null && supabaseId != null) {
        try {
          await Supabase.instance.client
              .from('labels')
              .update({'name': newLabel})
              .eq('id', supabaseId);
        } catch (e) {
          debugPrint('Label rename sync error: $e');
        }
      }

      await ActivityLogService().addLog(ActivityLogEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        action: 'modified',
        entityType: 'label',
        entityName: newLabel,
        inventoryId: _currentInventoryId,
        inventoryName: getInventoryName(_currentInventoryId!),
        details: 'Label renamed',
        changes: {'name': FieldChange(oldValue: oldLabel, newValue: newLabel)},
      ));
    }
  }

  Future<void> deleteLabel(String label) async {
    if (_currentInventoryId == null) return;

    if (!_labelsBoxes.containsKey(_currentInventoryId!)) {
      await initializeForInventory(_currentInventoryId!);
    }

    final supabaseId = getLabelInfo(label)?.supabaseId;
    final items = getItemsByLabel(label);
    final companyId = _currentCompanyId;

    // Sync to Supabase first (soft delete)
    if (AppConfig.useSupabase && companyId != null) {
      try {
        if (supabaseId != null) {
          await Supabase.instance.client
              .from('labels')
              .update({'is_deleted': true})
              .eq('id', supabaseId);
        }
        await Supabase.instance.client
            .from('inventory_items')
            .update({'is_deleted': true})
            .eq('company_id', companyId)
            .eq('label', label);
      } catch (e) {
        debugPrint('Label deletion sync error: $e');
      }
    }

    // Local deletion
    final currentLabels = _getCurrentLabelsList();
    currentLabels.remove(label);
    await _labelsBoxes[_currentInventoryId!]!.put('labels', currentLabels);

    final infos = Map<String, dynamic>.from(
      _labelsBoxes[_currentInventoryId!]!.get('labelInfos',
          defaultValue: <String, Map<String, dynamic>>{}) as Map,
    );
    infos.remove(label);
    await _saveLabelInfos(_currentInventoryId!, infos);

    for (var item in items) {
      await item.delete();
    }

    await ActivityLogService().addLog(ActivityLogEntry(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      action: 'deleted',
      entityType: 'label',
      entityName: label,
      inventoryId: _currentInventoryId,
      inventoryName: getInventoryName(_currentInventoryId!),
      details: 'Label deleted: "$label" with ${items.length} items',
    ));
  }

  List<String> _getCurrentLabelsList() {
    final labelsData = _labelsBoxes[_currentInventoryId!]!.get('labels');
    return labelsData is List ? List<String>.from(labelsData.cast<String>()) : [];
  }

  // ─── Item Management ───────────────────────────────────────────

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
    if (_currentInventoryId == null || !_itemsBoxes.containsKey(_currentInventoryId!)) {
      return;
    }

    if (item.key != null) {
      await item.save();
    } else {
      await _itemsBoxes[_currentInventoryId!]!.add(item);
    }

    await _syncItemToSupabase(item);
  }

  Future<int> importItems(String label, List<InventoryItem> newItems) async {
    if (_currentInventoryId == null) return 0;

    if (!_itemsBoxes.containsKey(_currentInventoryId!)) {
      await initializeForInventory(_currentInventoryId!);
    }

    final targetInventoryId = _currentInventoryId!;
    final box = _itemsBoxes[targetInventoryId]!;
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
          existing.note == newItem.note);

      if (!isDuplicate) {
        await box.add(newItem);
        if (_currentInventoryId == targetInventoryId) {
          await _syncItemToSupabase(newItem);
        }
        importedCount++;
      }
    }

    return importedCount;
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
          final map = Map<String, dynamic>.from(value);
          final name = map['name'] as String? ?? 'Unknown Inventory';
          names[key.toString()] = name;
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
        final map = Map<String, dynamic>.from(value);
        return map['name'] as String? ?? inventoryId;
      }
    } catch (e) {
      debugPrint('Error getting inventory name: $e');
    }
    return inventoryId;
  }

  // ─── Search ────────────────────────────────────────────────────

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

  // ─── Settings ──────────────────────────────────────────────────

  InventorySettings? get currentSettings {
    if (_currentInventoryId == null || !_isBoxAvailable('settings', _currentInventoryId)) {
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
    if (!_settingsBoxes.containsKey(_currentInventoryId!)) {
      await initializeForInventory(_currentInventoryId!);
    }

    final oldSettings = _settingsBoxes[_currentInventoryId!]!.get('main');
    await _settingsBoxes[_currentInventoryId!]!.put('main', settings);

    final changes = <String, FieldChange>{};
    if (oldSettings is InventorySettings) {
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

    await ActivityLogService().addLog(ActivityLogEntry(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      action: 'modified',
      entityType: 'settings',
      entityName: 'Settings',
      inventoryId: _currentInventoryId,
      inventoryName: getInventoryName(_currentInventoryId!),
      details: 'Settings updated',
      changes: changes.isNotEmpty ? changes : null,
    ));
  }

  // ─── Cleanup ───────────────────────────────────────────────────

  Future<void> dispose() async {
    await _closeAllBoxes();
    _currentInventoryId = null;
    _currentCompanyId = null;
    _lastSyncTimestamp = null;
  }
}