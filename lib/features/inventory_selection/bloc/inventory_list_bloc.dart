import 'package:flutter/foundation.dart';
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

  Future<void> _onLoad(
      LoadInventories event,
      Emitter<InventoryListState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));

    try {
      // Try to sync from Supabase first
      if (AppConfig.useSupabase) {
        try {
          final supabaseClient =
              Supabase.instance.client;
          final user = supabaseClient.auth.currentUser;

          if (user != null) {
            // Get user's company memberships
            final memberships = await supabaseClient
                .from('company_members')
                .select('company_id')
                .eq('user_id', user.id);

            if (memberships is List &&
                memberships.isNotEmpty) {
              for (final membership in memberships) {
                final companyId =
                    membership['company_id']
                            ?.toString() ??
                        '';

                if (companyId.isNotEmpty) {
                  // Fetch inventories for this company
                  final inventories =
                      await supabaseClient.rpc(
                          'get_company_inventories',
                          params: {
                        'p_company_id': companyId,
                      });

                  if (inventories is List) {
                    for (final inv
                        in inventories) {
                      final invMap = Map<String,
                          dynamic>.from(
                          inv as Map);
                      final invId =
                          invMap['id']
                                  ?.toString() ??
                              '';

                      if (invId.isNotEmpty) {
                        // Store in local Hive
                        await _inventoriesBox
                            .put(invId, {
                          'name': invMap['name']
                                  ?.toString() ??
                              'Inventory',
                          'created':
                              invMap['created_at']
                                      ?.toString() ??
                                  DateTime.now()
                                      .toIso8601String(),
                          'modified':
                              invMap['updated_at']
                                      ?.toString() ??
                                  DateTime.now()
                                      .toIso8601String(),
                          'company_id':
                              companyId,
                        });

                        // Initialize inventory service
                        await _inventoryService
                            .initializeForInventory(
                                invId);
                      }
                    }
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint(
              'Failed to sync inventories from Supabase: $e');
        }
      }

      // Load from local Hive
      final inventories = _loadFromBox();

      // Filter out any orphaned inventories (no company_id)
      final validInventories = inventories
          .where((inv) => _inventoriesBox
                  .get(inv.id)?['company_id'] !=
              null)
          .toList();

      emit(state.copyWith(
        inventories: validInventories,
        isLoading: false,
        isInitialized: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to load inventories: $e',
      ));
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

      // Get current user's company
      String? companyId;
      if (AppConfig.useSupabase) {
        try {
          final supabaseClient =
              Supabase.instance.client;
          final user = supabaseClient.auth.currentUser;

          if (user != null) {
            final memberships = await supabaseClient
                .from('company_members')
                .select('company_id')
                .eq('user_id', user.id)
                .limit(1)
                .maybeSingle();

            companyId =
                memberships?['company_id']?.toString();
          }
        } catch (_) {}
      }

      // Store locally
      await _inventoriesBox.put(id, {
        'name': name,
        'created': timestamp.toIso8601String(),
        'modified': timestamp.toIso8601String(),
        'company_id': companyId ?? '',
      });

      // Initialize inventory service
      await _inventoryService.initializeForInventory(id);

      // Sync to Supabase
      if (AppConfig.useSupabase &&
          companyId != null &&
          companyId.isNotEmpty) {
        try {
          await Supabase.instance.client
              .from('inventories')
              .insert({
            'id': id,
            'company_id': companyId,
            'name': name,
            'created_by': Supabase
                .instance.client.auth.currentUser?.id,
            'created_by_name': Supabase
                    .instance
                    .client
                    .auth
                    .currentUser
                    ?.userMetadata?['display_name'] ??
                Supabase
                    .instance.client.auth.currentUser
                    ?.email ??
                'Unknown',
            'created_at':
                timestamp.toUtc().toIso8601String(),
            'updated_at':
                timestamp.toUtc().toIso8601String(),
          });
        } catch (e) {
          debugPrint(
              'Failed to sync inventory to Supabase: $e');
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