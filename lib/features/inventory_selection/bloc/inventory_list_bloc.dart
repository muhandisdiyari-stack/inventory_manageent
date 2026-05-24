import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/inventory_list_item.dart';
import '../../inventory_management/services/inventory_service.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/config/app_config.dart';

part 'inventory_list_event.dart';
part 'inventory_list_state.dart';

class InventoryListBloc
    extends Bloc<InventoryListEvent, InventoryListState> {
  final InventoryService _inventoryService;
  final ActivityLogService _logService;
  final Box _inventoriesBox;
  static const _uuid = Uuid();

  InventoryListBloc({
    required InventoryService inventoryService,
    required ActivityLogService logService,
  })  : _inventoryService = inventoryService,
        _logService = logService,
        _inventoriesBox =
            Hive.box(AppConstants.inventoriesListBox),
        super(const InventoryListState()) {
    on<LoadInventories>(_onLoad);
    on<CreateInventory>(_onCreate);
    on<RenameInventory>(_onRename);
    on<DeleteInventory>(_onDelete);
    on<SelectInventory>(_onSelect);
  }

  List<InventoryListItem> _loadFromBox() {
    final items = <InventoryListItem>[];
    for (var key in _inventoriesBox.keys) {
      final value = _inventoriesBox.get(key);
      if (value is Map) {
        final typedMap = <String, dynamic>{};
        value
            .forEach((k, v) => typedMap[k.toString()] = v);
        final name = typedMap['name'] as String? ?? '';
        if (name.isNotEmpty) {
          items.add(InventoryListItem.fromMap(
              key.toString(), typedMap));
        }
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// ✅ Load inventories from Supabase AND local cache
  Future<void> _onLoad(
      LoadInventories event,
      Emitter<InventoryListState> emit) async {
    try {
      emit(state.copyWith(isLoading: true, error: null));

      // Try to fetch inventories from Supabase
      if (AppConfig.useSupabase) {
        try {
          final supabaseClient =
              Supabase.instance.client;

          // Get current user's company
          final user = supabaseClient.auth.currentUser;
          if (user != null) {
            final profileData = await supabaseClient
                .from('profiles')
                .select('company_id')
                .eq('id', user.id)
                .maybeSingle();

            final companyId =
                profileData?['company_id'] as String?;

            if (companyId != null) {
              // Fetch inventories for this company
              final supabaseInventories =
                  await supabaseClient
                      .rpc('get_company_inventories',
                          params: {
                        'p_company_id': companyId,
                      });

              if (supabaseInventories is List &&
                  supabaseInventories.isNotEmpty) {
                // Sync to local Hive boxes
                for (final inv
                    in supabaseInventories) {
                  final invMap = Map<String,
                      dynamic>.from(inv as Map);
                  final invId = invMap['id']
                          ?.toString() ??
                      '';

                  if (invId.isNotEmpty) {
                    // Initialize the inventory service for this inventory
                    await _inventoryService
                        .initializeForInventory(
                            invId);

                    // Store in local Hive box
                    await _inventoriesBox.put(invId, {
                      'name': invMap['name']
                              ?.toString() ??
                          'Unknown Inventory',
                      'created': invMap['created_at']
                              ?.toString() ??
                          DateTime.now()
                              .toIso8601String(),
                      'modified': invMap['updated_at']
                              ?.toString() ??
                          DateTime.now()
                              .toIso8601String(),
                      'company_id': companyId,
                    });
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint(
              'Failed to load inventories from Supabase: $e');
          // Continue with local cache
        }
      }

      // Load from local Hive box (which now includes synced data)
      final inventories = _loadFromBox();
      emit(state.copyWith(
          inventories: inventories, error: null));
    } catch (e) {
      emit(state.copyWith(
          error: 'Failed to load inventories: $e'));
    }
  }

  Future<void> _onCreate(
      CreateInventory event,
      Emitter<InventoryListState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final id = _uuid.v4();
      final timestamp = DateTime.now();
      final name = event.name.trim();

      // Store locally
      await _inventoriesBox.put(id, {
        'name': name,
        'created': timestamp.toIso8601String(),
        'modified': timestamp.toIso8601String(),
      });

      // Initialize the inventory service
      await _inventoryService.initializeForInventory(id);

      // ✅ Sync to Supabase if online
      if (AppConfig.useSupabase) {
        try {
          final supabaseClient =
              Supabase.instance.client;
          final user = supabaseClient.auth.currentUser;

          if (user != null) {
            // Get company ID
            final profileData = await supabaseClient
                .from('profiles')
                .select('company_id')
                .eq('id', user.id)
                .maybeSingle();

            final companyId = profileData?['company_id']
                as String?;

            if (companyId != null) {
              // Create inventory in Supabase
              await supabaseClient
                  .from('inventories')
                  .insert({
                'id': id,
                'company_id': companyId,
                'name': name,
                'created_by': user.id,
                'created_at': timestamp
                    .toUtc()
                    .toIso8601String(),
                'updated_at': timestamp
                    .toUtc()
                    .toIso8601String(),
              });
            }
          }
        } catch (e) {
          debugPrint(
              'Failed to sync inventory to Supabase: $e');
          // Inventory is saved locally, will sync later
        }
      }

      await _logService.addLog(ActivityLogEntry(
        id: _uuid.v4(),
        timestamp: timestamp,
        action: 'created',
        entityType: 'inventory',
        entityName: name,
        inventoryId: id,
        inventoryName: name,
        details: 'Inventory created: "$name"',
      ));

      final inventories = _loadFromBox();
      emit(state.copyWith(
        inventories: inventories,
        selectedInventoryId: id,
        selectedInventoryName: name,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
          isLoading: false,
          error: 'Failed to create inventory: $e'));
    }
  }

  Future<void> _onRename(
      RenameInventory event,
      Emitter<InventoryListState> emit) async {
    try {
      final data = _inventoriesBox.get(event.id);
      if (data is Map) {
        final typedMap = <String, dynamic>{};
        data.forEach(
            (k, v) => typedMap[k.toString()] = v);
        final oldName =
            typedMap['name'] as String? ?? '';
        typedMap['name'] = event.newName.trim();
        typedMap['modified'] =
            DateTime.now().toIso8601String();
        await _inventoriesBox.put(event.id, typedMap);

        // Sync to Supabase
        if (AppConfig.useSupabase) {
          try {
            await Supabase.instance.client
                .from('inventories')
                .update({
              'name': event.newName.trim(),
              'updated_at': DateTime.now()
                  .toUtc()
                  .toIso8601String(),
            }).eq('id', event.id);
          } catch (_) {}
        }

        await _logService.addLog(ActivityLogEntry(
          id: _uuid.v4(),
          timestamp: DateTime.now(),
          action: 'modified',
          entityType: 'inventory',
          entityName: event.newName.trim(),
          inventoryId: event.id,
          inventoryName: event.newName.trim(),
          details: 'Inventory renamed',
          changes: {
            'name': FieldChange(
                oldValue: oldName,
                newValue: event.newName.trim())
          },
        ));
        final inventories = _loadFromBox();
        emit(state.copyWith(inventories: inventories));
      }
    } catch (e) {
      emit(state.copyWith(error: 'Failed to rename: $e'));
    }
  }

  Future<void> _onDelete(
      DeleteInventory event,
      Emitter<InventoryListState> emit) async {
    try {
      final data = _inventoriesBox.get(event.id);
      final inventoryName = data is Map
          ? (data['name'] as String? ?? '')
          : '';

      await _logService.addLog(ActivityLogEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        action: 'deleted',
        entityType: 'inventory',
        entityName: inventoryName,
        inventoryId: event.id,
        inventoryName: inventoryName,
        details: 'Inventory deleted: "$inventoryName"',
      ));

      // Soft delete in Supabase
      if (AppConfig.useSupabase) {
        try {
          await Supabase.instance.client
              .from('inventories')
              .update({
            'is_deleted': true,
            'updated_at': DateTime.now()
                .toUtc()
                .toIso8601String(),
          }).eq('id', event.id);
        } catch (_) {}
      }

      await _logService.clearLogs(inventoryId: event.id);
      await _inventoryService
          .deleteInventoryData(event.id);
      await _inventoriesBox.delete(event.id);

      final inventories = _loadFromBox();
      final newSelectedId =
          state.selectedInventoryId == event.id
              ? (inventories.isNotEmpty
                  ? inventories.first.id
                  : null)
              : state.selectedInventoryId;
      emit(state.copyWith(
        inventories: inventories,
        selectedInventoryId: newSelectedId,
      ));
    } catch (e) {
      emit(state.copyWith(
          error: 'Failed to delete: $e'));
    }
  }

  void _onSelect(
      SelectInventory event,
      Emitter<InventoryListState> emit) {
    String? name;
    final data = _inventoriesBox.get(event.id);
    if (data is Map) {
      final typedMap = <String, dynamic>{};
      data.forEach(
          (k, v) => typedMap[k.toString()] = v);
      name = typedMap['name'] as String?;
    }
    emit(state.copyWith(
      selectedInventoryId: event.id,
      selectedInventoryName: name,
    ));
  }
}