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

class InventoryListBloc extends Bloc<InventoryListEvent, InventoryListState> {
  final InventoryService _inventoryService;
  final ActivityLogService _logService;
  final Box _inventoriesBox;
  static const _uuid = Uuid();

  InventoryListBloc({
    required InventoryService inventoryService,
    required ActivityLogService logService,
  })  : _inventoryService = inventoryService,
        _logService = logService,
        _inventoriesBox = Hive.box(AppConstants.inventoriesListBox),
        super(const InventoryListState()) {
    on<LoadInventories>(_onLoad);
    on<CreateInventory>(_onCreate);
    on<RenameInventory>(_onRename);
    on<DeleteInventory>(_onDelete);
    on<SelectInventory>(_onSelect);
  }

  /// Get the current user's active company ID from Supabase
  Future<String?> _getCurrentCompanyId() async {
    if (!AppConfig.useSupabase) return null;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;
      
      final memberships = await Supabase.instance.client
          .from('company_members')
          .select('company_id')
          .eq('user_id', user.id)
          .limit(1)
          .maybeSingle();
      
      return memberships?['company_id']?.toString();
    } catch (e) {
      debugPrint('Failed to get company ID: $e');
      return null;
    }
  }

  Future<void> _onLoad(
      LoadInventories event, Emitter<InventoryListState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));

    try {
      final companyId = await _getCurrentCompanyId();
      
      // Clear old local cache that doesn't belong to this company
      if (companyId != null) {
        final keysToRemove = <String>[];
        for (var key in _inventoriesBox.keys) {
          final value = _inventoriesBox.get(key);
          if (value is Map) {
            final storedCompanyId = value['company_id']?.toString() ?? '';
            if (storedCompanyId.isNotEmpty && storedCompanyId != companyId) {
              keysToRemove.add(key.toString());
            }
          }
        }
        for (var key in keysToRemove) {
          await _inventoriesBox.delete(key);
        }
      }

      // Sync from Supabase
      if (AppConfig.useSupabase && companyId != null) {
        try {
          final inventories = await Supabase.instance.client
              .rpc('get_company_inventories', params: {'p_company_id': companyId});

          if (inventories is List) {
            for (final inv in inventories) {
              final invMap = Map<String, dynamic>.from(inv as Map);
              final invId = invMap['id']?.toString() ?? '';
              if (invId.isNotEmpty) {
                await _inventoriesBox.put(invId, {
                  'name': invMap['name']?.toString() ?? 'Inventory',
                  'created': invMap['created_at']?.toString() ?? DateTime.now().toIso8601String(),
                  'modified': invMap['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
                  'company_id': companyId,
                });
                await _inventoryService.initializeForInventory(invId);
              }
            }
          }
        } catch (e) {
          debugPrint('Failed to sync inventories: $e');
        }
      }

      // Load from Hive (only this company's inventories)
      final allItems = <InventoryListItem>[];
      for (var key in _inventoriesBox.keys) {
        final value = _inventoriesBox.get(key);
        if (value is Map) {
          final itemCompanyId = value['company_id']?.toString() ?? '';
          if (companyId == null || itemCompanyId == companyId || itemCompanyId.isEmpty) {
            final name = value['name']?.toString() ?? '';
            if (name.isNotEmpty) {
              allItems.add(InventoryListItem.fromMap(key.toString(), Map<String, dynamic>.from(value)));
            }
          }
        }
      }
      allItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      emit(state.copyWith(
        inventories: allItems,
        isLoading: false,
        isInitialized: true,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: 'Failed to load: $e'));
    }
  }

  Future<void> _onCreate(
      CreateInventory event, Emitter<InventoryListState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final id = _uuid.v4();
      final timestamp = DateTime.now();
      final name = event.name.trim();
      final companyId = await _getCurrentCompanyId();

      await _inventoriesBox.put(id, {
        'name': name,
        'created': timestamp.toIso8601String(),
        'modified': timestamp.toIso8601String(),
        'company_id': companyId ?? '',
      });

      await _inventoryService.initializeForInventory(id);

      if (AppConfig.useSupabase && companyId != null) {
        try {
          final user = Supabase.instance.client.auth.currentUser;
          await Supabase.instance.client.from('inventories').insert({
            'id': id,
            'company_id': companyId,
            'name': name,
            'created_by': user?.id,
            'created_by_name': user?.userMetadata?['display_name'] ?? user?.email ?? 'Unknown',
            'created_at': timestamp.toUtc().toIso8601String(),
            'updated_at': timestamp.toUtc().toIso8601String(),
          });
        } catch (e) {
          debugPrint('Failed to sync: $e');
        }
      }

      final items = _loadFromBox(companyId);
      emit(state.copyWith(
        inventories: items,
        selectedInventoryId: id,
        selectedInventoryName: name,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: 'Failed to create: $e'));
    }
  }

  List<InventoryListItem> _loadFromBox(String? companyId) {
    final items = <InventoryListItem>[];
    for (var key in _inventoriesBox.keys) {
      final value = _inventoriesBox.get(key);
      if (value is Map) {
        final itemCompanyId = value['company_id']?.toString() ?? '';
        if (companyId == null || itemCompanyId == companyId || itemCompanyId.isEmpty) {
          final name = value['name']?.toString() ?? '';
          if (name.isNotEmpty) {
            items.add(InventoryListItem.fromMap(key.toString(), Map<String, dynamic>.from(value)));
          }
        }
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<void> _onRename(RenameInventory event, Emitter<InventoryListState> emit) async {
    try {
      final data = _inventoriesBox.get(event.id);
      if (data is Map) {
        final typedMap = Map<String, dynamic>.from(data);
        typedMap['name'] = event.newName.trim();
        typedMap['modified'] = DateTime.now().toIso8601String();
        await _inventoriesBox.put(event.id, typedMap);
        
        if (AppConfig.useSupabase) {
          try {
            await Supabase.instance.client.from('inventories')
                .update({'name': event.newName.trim(), 'updated_at': DateTime.now().toUtc().toIso8601String()})
                .eq('id', event.id);
          } catch (_) {}
        }
        
        final companyId = await _getCurrentCompanyId();
        emit(state.copyWith(inventories: _loadFromBox(companyId)));
      }
    } catch (e) {
      emit(state.copyWith(error: 'Failed to rename: $e'));
    }
  }

  Future<void> _onDelete(DeleteInventory event, Emitter<InventoryListState> emit) async {
    try {
      if (AppConfig.useSupabase) {
        try {
          await Supabase.instance.client.from('inventories')
              .update({'is_deleted': true, 'updated_at': DateTime.now().toUtc().toIso8601String()})
              .eq('id', event.id);
        } catch (_) {}
      }
      
      await _inventoryService.deleteInventoryData(event.id);
      await _inventoriesBox.delete(event.id);
      
      final companyId = await _getCurrentCompanyId();
      final inventories = _loadFromBox(companyId);
      emit(state.copyWith(
        inventories: inventories,
        selectedInventoryId: state.selectedInventoryId == event.id
            ? (inventories.isNotEmpty ? inventories.first.id : null)
            : state.selectedInventoryId,
      ));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to delete: $e'));
    }
  }

  void _onSelect(SelectInventory event, Emitter<InventoryListState> emit) {
    String? name;
    final data = _inventoriesBox.get(event.id);
    if (data is Map) {
      name = data['name']?.toString();
    }
    emit(state.copyWith(selectedInventoryId: event.id, selectedInventoryName: name));
  }
}