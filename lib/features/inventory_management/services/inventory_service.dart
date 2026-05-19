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

  // FIX #8: Cache parsed labelInfos to avoid repeated JSON deserialization.
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
      // FIX #7: Flush all pending writes before closing boxes to prevent
      // in-flight write loss.
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
      final settingsBox =
          await Hive.openBox<InventorySettings>(settingsBoxName);
      if (!settingsBox.containsKey('main')) {
        await settingsBox.put('main', InventorySettings());
      }
      _settingsBoxes[inventoryId] = settingsBox;

      _currentInventoryId = inventoryId;

      // Invalidate label infos cache for this inventory on fresh init
      _labelInfosCache.remove(inventoryId);

      // Load company ID for sync
      await _loadCompanyId();

      // Sync with Supabase if enabled
      if (AppConfig.useSupabase) {
        await _syncLabelsWithSupabase(inventoryId);
        await _loadAndMergeSupabaseItems(inventoryId);
      }
    } catch (e) {
      debugPrint('Error initializing inventory $inventoryId: $e');
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _closeAllBoxes() async {
    // FIX #7: Flush pending writes before closing each box.
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
    // Clear the cache when all boxes are closed
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
      // FIX #7: Flush before closing to ensure no data loss.
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

      // Invalidate label infos cache for deleted inventory
      _labelInfosCache.remove(id);

      // FIX #5: Use Hive.deleteBoxFromDisk — avoids re-opening typed boxes
      // with the wrong generic type (Hive.box() returns Box<dynamic> which
      // throws for typed boxes).
      await _deleteBoxSafely('items_$id');
      await _deleteBoxSafely('labels_$id');
      await _deleteBoxSafely('inventory_settings_$id');

      if (_currentInventoryId == id) {
        _currentInventoryId = null;
      }

      // Clean up Supabase if applicable
      final companyId = _currentCompanyId;
      if (AppConfig.useSupabase && companyId != null) {
        try {
          await Supabase.instance.client
              .from('inventory_items')
              .delete()
              .eq('inventory_id', id)
              .eq('company_id', companyId);
        } catch (e) {
          debugPrint('Supabase cleanup error for inventory $id: $e');
        }
      }

      debugPrint('=== Inventory data deleted successfully: $id ===');
    } catch (e) {
      debugPrint('=== Error deleting inventory data: $e ===');
      rethrow;
    }
  }

  // FIX #5: Use Hive.deleteBoxFromDisk instead of Hive.box() to avoid a
  // runtime type error when the box was registered as a typed Box<T>.
  // Hive.box() returns Box<dynamic> for a named open box, which throws when
  // the box was originally opened as Box<InventoryItem>.
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

      // Load labels from Supabase
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

      // Merge Supabase labels into local
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
        // Update local labels list
        final currentLabels = List<String>.from(
          _labelsBoxes[inventoryId]!
              .get('labels', defaultValue: <String>[]) as List,
        );

        for (final name in localInfos.keys) {
          if (!currentLabels.contains(name)) {
            currentLabels.add(name);
          }
        }

        await _labelsBoxes[inventoryId]!.put('labels', currentLabels);
        await _labelsBoxes[inventoryId]!.put('labelInfos', localInfos);

        // Invalidate cache after write
        _labelInfosCache.remove(inventoryId);
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
        'created_by_name':
            user.userMetadata?['display_name'] ?? user.email ?? 'Unknown',
        'updated_at': now,
      };

      // Check if item has a Supabase ID stored
      final supabaseId = item.customFields['_supabase_id'];

      if (supabaseId != null && supabaseId.isNotEmpty) {
        // Update existing Supabase record
        data['id'] = supabaseId;
        await client.from('inventory_items').update(data).eq('id', supabaseId);
        debugPrint('🔄 Item updated in Supabase: ${item.name}');
      } else {
        // Insert new record
        final newId = _uuid.v4();
        data['id'] = newId;
        data['created_at'] = item.createdAt.toUtc().toIso8601String();
        await client.from('inventory_items').insert(data);

        // Store Supabase ID locally for future syncs
        item.customFields['_supabase_id'] = newId;
        await item.save();
        debugPrint('✅ New item synced to Supabase: ${item.name}');
      }
    } catch (e) {
      debugPrint('❌ Sync error for item ${item.name}: $e');
    }
  }

  Future<void> _loadAndMergeSupabaseItems(String inventoryId) async {
    if (!AppConfig.useSupabase) return;

    final companyId = _currentCompanyId;
    if (companyId == null) return;

    try {
      final client = Supabase.instance.client;

      // FIX #4: Added .eq('inventory_id', inventoryId) filter to prevent
      // items from other inventories in the same company being merged into
      // the current inventory, which was a cross-inventory data leak.
      PostgrestFilterBuilder<PostgrestList> query = client
          .from('inventory_items')
          .select()
          .eq('company_id', companyId)
          .eq('inventory_id', inventoryId)
          .eq('is_deleted', false);

      // Incremental sync if we have a last sync timestamp
      if (_lastSyncTimestamp != null) {
        query = query.gt(
          'updated_at',
          _lastSyncTimestamp!.toUtc().toIso8601String(),
        );
      }

      // .order() returns PostgrestTransformBuilder, so we resolve the full
      // query into a final awaitable rather than assigning back to the
      // PostgrestFilterBuilder variable (which would be a type mismatch).
      final supabaseItems = await query.order('updated_at', ascending: false);

      final box = _itemsBoxes[inventoryId];
      if (box == null) return;

      int updatedCount = 0;
      int addedCount = 0;

      for (final itemData in supabaseItems) {
        final supabaseId = itemData['id'] as String?;
        if (supabaseId == null) continue;

        // Find existing item by Supabase ID
        InventoryItem? existingItem;
        for (final item in box.values) {
          if (item.customFields['_supabase_id'] == supabaseId) {
            existingItem = item;
            break;
          }
        }

        if (existingItem != null) {
          // Update existing item if Supabase version is newer
          final supabaseUpdated = itemData['updated_at'] != null
              ? DateTime.parse(itemData['updated_at'] as String)
              : DateTime.now();

          if (supabaseUpdated.isAfter(existingItem.modified)) {
            existingItem.name =
                itemData['name'] as String? ?? existingItem.name;
            existingItem.code =
                itemData['code'] as String? ?? existingItem.code;
            existingItem.barcode =
                itemData['barcode'] as String? ?? existingItem.barcode;
            existingItem.color =
                itemData['color'] as String? ?? existingItem.color;
            existingItem.material =
                itemData['material'] as String? ?? existingItem.material;
            existingItem.size =
                itemData['size'] as String? ?? existingItem.size;
            existingItem.quantity =
                itemData['quantity'] as int? ?? existingItem.quantity;
            existingItem.label =
                itemData['label'] as String? ?? existingItem.label;
            existingItem.note =
                itemData['note'] as String? ?? existingItem.note;

            // Merge custom fields
            final supabaseCustomFields =
                itemData['custom_fields'] as Map<String, dynamic>?;
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
          // Create new local item from Supabase data
          final customFields = <String, String>{
            '_supabase_id': supabaseId,
          };

          final supabaseCustomFields =
              itemData['custom_fields'] as Map<String, dynamic>?;
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

      // Update sync timestamp
      _lastSyncTimestamp = DateTime.now();

      debugPrint(
        '✅ Synced ${supabaseItems.length} items from Supabase '
        '($updatedCount updated, $addedCount added)',
      );
    } catch (e) {
      debugPrint('❌ Load from Supabase error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> loadItemsFromSupabase(
      String inventoryId) async {
    if (!AppConfig.useSupabase) return [];

    final companyId = _currentCompanyId;
    if (companyId == null) return [];

    try {
      final client = Supabase.instance.client;
      final data = await client
          .from('inventory_items')
          .select()
          .eq('company_id', companyId)
          .eq('is_deleted', false)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Load from Supabase error: $e');
      return [];
    }
  }

  // ─── Label Management ──────────────────────────────────────────

  // FIX #8: Cache parsed LabelInfo map per inventory to avoid repeated JSON
  // deserialization on every call to labelInfos (which is called from
  // getSortedLabels, getLabelInfo, renameLabel, deleteLabel, etc.).
  // Cache is invalidated whenever the box is written to.
  Map<String, LabelInfo> _parseLabelInfos(String inventoryId) {
    final rawMap =
        _labelsBoxes[inventoryId]!.get('labelInfos');
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
    if (_currentInventoryId == null ||
        !_isBoxAvailable('labels', _currentInventoryId)) {
      return {};
    }
    // Return cached version if available, otherwise parse and cache
    return _labelInfosCache[_currentInventoryId!] ??=
        _parseLabelInfos(_currentInventoryId!);
  }

  /// Writes updated label infos to the box and invalidates the cache.
  Future<void> _saveLabelInfos(
      String inventoryId, Map<String, dynamic> infos) async {
    await _labelsBoxes[inventoryId]!.put('labelInfos', infos);
    // Invalidate cache so next access re-parses from the box
    _labelInfosCache.remove(inventoryId);
  }

  List<String> get labels => getSortedLabels();

  bool get hasLabels {
    if (_currentInventoryId == null ||
        !_isBoxAvailable('labels', _currentInventoryId)) {
      return false;
    }
    final labelsData = _labelsBoxes[_currentInventoryId!]!.get('labels');
    return labelsData is List && labelsData.isNotEmpty;
  }

  bool hasLabel(String label) {
    if (_currentInventoryId == null ||
        !_isBoxAvailable('labels', _currentInventoryId)) {
      return false;
    }
    final labelsData = _labelsBoxes[_currentInventoryId!]!.get('labels');
    return labelsData is List && labelsData.contains(label);
  }

  List<String> getSortedLabels({
    LabelSortType sortType = LabelSortType.nameAsc,
  }) {
    if (_currentInventoryId == null ||
        !_isBoxAvailable('labels', _currentInventoryId)) {
      return [];
    }
    final infos = labelInfos;
    if (infos.isEmpty) return [];

    final sortedEntries = infos.entries.toList();

    switch (sortType) {
      case LabelSortType.nameAsc:
        sortedEntries.sort(
            (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
      case LabelSortType.nameDesc:
        sortedEntries.sort(
            (a, b) => b.key.toLowerCase().compareTo(a.key.toLowerCase()));
      case LabelSortType.dateCreatedAsc:
        sortedEntries
            .sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
      case LabelSortType.dateCreatedDesc:
        sortedEntries
            .sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));
      case LabelSortType.dateModifiedAsc:
        sortedEntries
            .sort((a, b) => a.value.modifiedAt.compareTo(b.value.modifiedAt));
      case LabelSortType.dateModifiedDesc:
        sortedEntries
            .sort((a, b) => b.value.modifiedAt.compareTo(a.value.modifiedAt));
    }

    return sortedEntries.map((e) => e.key).toList();
  }

  LabelInfo? getLabelInfo(String labelName) {
    if (_currentInventoryId == null ||
        !_isBoxAvailable('labels', _currentInventoryId)) {
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

      // Use helper so cache is invalidated
      await _saveLabelInfos(_currentInventoryId!, infos);

      // Sync label to Supabase
      final companyId = _currentCompanyId;
      if (AppConfig.useSupabase && companyId != null) {
        try {
          final client = Supabase.instance.client;
          final result = await client.from('labels').insert({
            'company_id': companyId,
            'name': label,
          }).select().single();

          // result from .single() is non-nullable — it throws on no rows,
          // so a null check here is unnecessary and was a lint warning.
          final updatedInfos = Map<String, dynamic>.from(
            _labelsBoxes[_currentInventoryId!]!.get('labelInfos',
                defaultValue: <String, Map<String, dynamic>>{}) as Map,
          );
          final existingInfo = updatedInfos[label] as Map<String, dynamic>?;
          if (existingInfo != null) {
            final info =
                LabelInfo.fromJson(Map<String, dynamic>.from(existingInfo));
            updatedInfos[label] = info.copyWith(
              supabaseId: result['id'] as String?,
              modifiedAt: DateTime.now(),
              isSynced: true,
            ).toJson();
            await _saveLabelInfos(_currentInventoryId!, updatedInfos);
          }
        } catch (e) {
          debugPrint('Label sync to Supabase error: $e');
        }
      }

      // FIX #9: Use uuid v4 instead of microsecondsSinceEpoch to avoid ID
      // collisions when multiple log entries are created in rapid succession
      // (e.g. during bulk label creation).
      final logEntry = ActivityLogEntry(
        id: _uuid.v4(),
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
      // FIX #2: Capture the supabaseId from the old label BEFORE modifying
      // the infos map. Previously it was read after the rename write, at which
      // point labelInfos[oldLabel] no longer exists (the key was removed and
      // labelInfos[newLabel] was written with isSynced:false, potentially
      // losing the supabaseId in the lookup).
      final supabaseId = getLabelInfo(oldLabel)?.supabaseId;

      currentLabels[index] = newLabel;
      await _labelsBoxes[_currentInventoryId!]!.put('labels', currentLabels);

      // Update label infos
      final infos = Map<String, dynamic>.from(
        _labelsBoxes[_currentInventoryId!]!.get('labelInfos',
            defaultValue: <String, Map<String, dynamic>>{}) as Map,
      );
      final oldInfo = infos[oldLabel];
      if (oldInfo is Map) {
        final labelInfo =
            LabelInfo.fromJson(Map<String, dynamic>.from(oldInfo));
        infos.remove(oldLabel);
        infos[newLabel] = labelInfo.copyWith(
          name: newLabel,
          modifiedAt: DateTime.now(),
          isSynced: false,
        ).toJson();
        await _saveLabelInfos(_currentInventoryId!, infos);
      }

      // Update all items with this label
      final items = getItemsByLabel(oldLabel);
      for (var item in items) {
        item.label = newLabel;
        await item.save();
        await _syncItemToSupabase(item);
      }

      // Sync label rename to Supabase using the pre-captured supabaseId
      final companyId = _currentCompanyId;
      if (AppConfig.useSupabase && companyId != null) {
        try {
          if (supabaseId != null) {
            await Supabase.instance.client
                .from('labels')
                .update({'name': newLabel}).eq('id', supabaseId);
          }
        } catch (e) {
          debugPrint('Label rename sync error: $e');
        }
      }

      // FIX #9: Use uuid v4 for log entry ID
      final logEntry = ActivityLogEntry(
        id: _uuid.v4(),
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

    // FIX #1: Capture the supabaseId and item list BEFORE modifying local
    // state. Previously the supabaseId was read after infos.remove(label) was
    // written to the box, so labelInfos[label] always returned null and the
    // Supabase soft-delete for the label record was silently skipped.
    final supabaseId = getLabelInfo(label)?.supabaseId;
    final items = getItemsByLabel(label);

    // FIX #3: Perform the Supabase soft-delete BEFORE the local hard-delete.
    // This ensures Supabase records are marked is_deleted:true before local
    // items are removed. If the order were reversed, a sync triggered between
    // local deletion and Supabase update could re-import the deleted items.
    final companyId = _currentCompanyId;
    if (AppConfig.useSupabase && companyId != null) {
      try {
        if (supabaseId != null) {
          await Supabase.instance.client
              .from('labels')
              .update({'is_deleted': true}).eq('id', supabaseId);
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

    // Now perform local deletion
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

    // FIX #9: Use uuid v4 for log entry ID
    final logEntry = ActivityLogEntry(
      id: _uuid.v4(),
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
    return labelsData is List
        ? List<String>.from(labelsData.cast<String>())
        : [];
  }

  // ─── Item Management ───────────────────────────────────────────

  List<InventoryItem> getItemsByLabel(String label) {
    if (_currentInventoryId == null ||
        !_isBoxAvailable('items', _currentInventoryId)) {
      return [];
    }
    return _itemsBoxes[_currentInventoryId!]!.values
        .where((item) => item.label == label)
        .toList();
  }

  List<InventoryItem> getItems(String label) => getItemsByLabel(label);

  Future<void> saveItem(InventoryItem item) async {
    if (_currentInventoryId == null ||
        !_itemsBoxes.containsKey(_currentInventoryId!)) {
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

    // FIX #6: Ensure _currentInventoryId matches the target label's inventory
    // before syncing. If selectInventory was called with a different ID between
    // the guard above and the sync call below, items would be synced to the
    // wrong inventory in Supabase.
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
        // Only sync if _currentInventoryId still matches our target
        if (_currentInventoryId == targetInventoryId) {
          await _syncItemToSupabase(newItem);
        }
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

    // FIX #6: Capture the target inventory ID at the start to guard against
    // _currentInventoryId drifting mid-operation during inventory switches.
    final targetInventoryId = _currentInventoryId!;

    final box = _itemsBoxes[targetInventoryId]!;
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
        if (_currentInventoryId == targetInventoryId) {
          await _syncItemToSupabase(item);
        }
        keysUsed.add(item.key!);
      } else {
        await box.add(item);
        if (_currentInventoryId == targetInventoryId) {
          await _syncItemToSupabase(item);
        }
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

        final inventoryName =
            inventoryNames[inventoryId] ?? getInventoryName(inventoryId);

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
        item.customFields.values
            .any((v) => v.toLowerCase().contains(lowerQuery));
  }

  // ─── Settings ──────────────────────────────────────────────────

  InventorySettings? get currentSettings {
    if (_currentInventoryId == null ||
        !_isBoxAvailable('settings', _currentInventoryId)) {
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
          .map((f) =>
              '${f.fieldName}(${f.isRequired ? "required" : "optional"})')
          .join(', ');
      final newFields = settings.fieldConfigs
          .where((f) => f.isEnabled)
          .map((f) =>
              '${f.fieldName}(${f.isRequired ? "required" : "optional"})')
          .join(', ');
      if (oldFields != newFields) {
        changes['fieldConfigs'] =
            FieldChange(oldValue: oldFields, newValue: newFields);
      }
      final oldCustom = oldSettings.customFieldNames.join(', ');
      final newCustom = settings.customFieldNames.join(', ');
      if (oldCustom != newCustom) {
        changes['customFields'] =
            FieldChange(oldValue: oldCustom, newValue: newCustom);
      }
    }

    // FIX #9: Use uuid v4 for log entry ID
    final logEntry = ActivityLogEntry(
      id: _uuid.v4(),
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

  // ─── Cleanup ───────────────────────────────────────────────────

  Future<void> dispose() async {
    await _closeAllBoxes();
    _currentInventoryId = null;
    _currentCompanyId = null;
    _lastSyncTimestamp = null;
  }
}