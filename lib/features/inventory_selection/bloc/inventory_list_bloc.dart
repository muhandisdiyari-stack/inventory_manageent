import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final Box _cacheBox;

  InventoryListBloc({
    required InventoryService inventoryService,
    required ActivityLogService logService,
  })  : _inventoryService = inventoryService,
        _logService = logService,
        _cacheBox = Hive.box(AppConstants.inventoriesListBox),
        super(const InventoryListState()) {
    on<LoadInventories>(_onLoad);
    on<CreateInventory>(_onCreate);
    on<RenameInventory>(_onRename);
    on<DeleteInventory>(_onDelete);
    on<SelectInventory>(_onSelect);
    on<RefreshInventories>(_onRefresh);
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════

  Future<String?> _getCurrentCompanyId() async {
    if (!AppConfig.useSupabase) return null;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;
      final data = await Supabase.instance.client
          .from('company_members')
          .select('company_id')
          .eq('user_id', user.id)
          .limit(1)
          .maybeSingle();
      return data?['company_id']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Read inventory list from local Hive cache
  List<InventoryListItem> _readCache(String? companyId) {
    final items = <InventoryListItem>[];
    final raw = _cacheBox.get('cached_inventories');
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final itemCompanyId = map['company_id']?.toString() ?? '';
          if (companyId == null || itemCompanyId == companyId) {
            items.add(InventoryListItem.fromMap(
                map['id']?.toString() ?? '', map));
          }
        }
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// Write inventory list to local Hive cache
  Future<void> _writeCache(List<Map<String, dynamic>> data) async {
    await _cacheBox.put('cached_inventories', data);
  }

  /// Get raw cache list as mutable list
  List<Map<String, dynamic>> _getRawCache() {
    final raw = _cacheBox.get('cached_inventories');
    if (raw is List) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// Fetch inventories from Supabase and return as list
  Future<List<Map<String, dynamic>>> _fetchFromSupabase(
      String companyId) async {
    final data = await Supabase.instance.client
        .rpc('get_company_inventories',
            params: {'p_company_id': companyId});

    if (data is List) {
      return data
          .map((inv) => Map<String, dynamic>.from(inv as Map))
          .toList();
    }
    return [];
  }

  // ═══════════════════════════════════════════════════════════════
  // LOAD: Supabase → Replace cache → State
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onLoad(
      LoadInventories event, Emitter<InventoryListState> emit) async {
    final companyId = await _getCurrentCompanyId();

    // Show cached data immediately for fast loading
    final cached = _readCache(companyId);
    if (cached.isNotEmpty) {
      emit(state.copyWith(
        inventories: cached,
        isLoading: false,
        isInitialized: true,
        isOffline: false,
      ));
    } else {
      emit(state.copyWith(isLoading: true));
    }

    // Try to fetch fresh data from Supabase
    if (AppConfig.useSupabase && companyId != null) {
      try {
        final freshData = await _fetchFromSupabase(companyId);

        // Replace entire cache with fresh data
        await _writeCache(freshData);

        // Initialize inventory service for each (but don't block UI)
        for (final inv in freshData) {
          final id = inv['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            try {
              await _inventoryService.initializeForInventory(id);
            } catch (_) {
              // Silently continue — individual inventory init failure
              // shouldn't block the whole list
            }
          }
        }

        // Emit fresh data
        final items = _readCache(companyId);
        if (!isClosed) {
          emit(state.copyWith(
            inventories: items,
            isLoading: false,
            isOffline: false,
            isInitialized: true,
          ));
        }
      } catch (e) {
        // Network error - keep showing cached data
        if (!isClosed) {
          emit(state.copyWith(
            inventories: cached,
            isLoading: false,
            isOffline: cached.isNotEmpty ? true : false,
            error: cached.isEmpty ? 'No connection. Pull to retry.' : null,
          ));
        }
      }
    } else {
      if (!isClosed) {
        emit(state.copyWith(
          inventories: cached,
          isLoading: false,
          isOffline: true,
        ));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // REFRESH: Force reload from Supabase
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onRefresh(
      RefreshInventories event, Emitter<InventoryListState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    add(const LoadInventories());
  }

  // ═══════════════════════════════════════════════════════════════
  // CREATE: Supabase FIRST → On success, add to cache → State
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onCreate(
      CreateInventory event, Emitter<InventoryListState> emit) async {
    final name = event.name.trim();
    final companyId = await _getCurrentCompanyId();

    if (!AppConfig.useSupabase || companyId == null) {
      if (!isClosed) {
        emit(state.copyWith(
          isLoading: false,
          error: 'Cannot create while offline',
        ));
      }
      return;
    }

    if (!isClosed) {
      emit(state.copyWith(isLoading: true, error: null));
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      final timestamp = DateTime.now();

      // 1. INSERT into Supabase and get the created record back
      final response = await Supabase.instance.client
          .from('inventories')
          .insert({
            'company_id': companyId,
            'name': name,
            'created_by': user?.id,
            'created_by_name':
                user?.userMetadata?['display_name'] ?? user?.email ?? 'Unknown',
            'created_at': timestamp.toUtc().toIso8601String(),
            'updated_at': timestamp.toUtc().toIso8601String(),
          })
          .select();

      if (response.isEmpty) {
  if (!isClosed) {
    emit(state.copyWith(
      isLoading: false,
      error: 'Failed to create inventory',
    ));
  }
  return;
}

      // 2. Parse the created record
      final created = Map<String, dynamic>.from(response.first as Map);
      final newId = created['id']?.toString() ?? '';

      debugPrint('✅ Created inventory: id=$newId name=$name');

      // 3. Add to local cache
      final cacheList = _getRawCache();
      cacheList.add({
        'id': newId,
        'name': name,
        'created_at':
            created['created_at']?.toString() ?? timestamp.toIso8601String(),
        'updated_at':
            created['updated_at']?.toString() ?? timestamp.toIso8601String(),
        'company_id': companyId,
        'created_by': user?.id,
        'created_by_name': created['created_by_name']?.toString() ?? '',
      });
      await _writeCache(cacheList);

      // 4. Initialize inventory service
      await _inventoryService.initializeForInventory(newId);

      // 5. Log activity
      await _logService.addLog(ActivityLogEntry(
        id: newId,
        timestamp: timestamp,
        action: 'created',
        entityType: 'inventory',
        entityName: name,
        inventoryId: newId,
        inventoryName: name,
        details: 'Created: "$name"',
      ));

      // 6. Emit state with new inventory included
      if (!isClosed) {
        final items = _readCache(companyId);
        emit(state.copyWith(
          inventories: items,
          selectedInventoryId: newId,
          selectedInventoryName: name,
          isLoading: false,
        ));
      }

      // 7. Silently refresh from Supabase in background
      _backgroundSync(companyId);
    } catch (e) {
      debugPrint('❌ Create inventory error: $e');
      if (!isClosed) {
        emit(state.copyWith(
          isLoading: false,
          error: 'Failed to create: $e',
        ));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // RENAME: Supabase FIRST → On success, update cache → State
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onRename(
      RenameInventory event, Emitter<InventoryListState> emit) async {
    try {
      if (AppConfig.useSupabase) {
        // 1. Update in Supabase
        await Supabase.instance.client.from('inventories').update({
          'name': event.newName.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', event.id);
      }

      // 2. Update in cache
      final cacheList = _getRawCache();
      for (final item in cacheList) {
        if (item['id']?.toString() == event.id) {
          item['name'] = event.newName.trim();
          item['updated_at'] = DateTime.now().toIso8601String();
          break;
        }
      }
      await _writeCache(cacheList);

      // 3. Log
      await _logService.addLog(ActivityLogEntry(
        id: event.id,
        timestamp: DateTime.now(),
        action: 'modified',
        entityType: 'inventory',
        entityName: event.newName.trim(),
        inventoryId: event.id,
        inventoryName: event.newName.trim(),
        details: 'Renamed',
      ));

      // 4. Emit
      if (!isClosed) {
        final companyId = await _getCurrentCompanyId();
        emit(state.copyWith(inventories: _readCache(companyId)));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(error: 'Failed to rename: $e'));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DELETE: Supabase FIRST → On success, remove from cache → State
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onDelete(
      DeleteInventory event, Emitter<InventoryListState> emit) async {
    if (!isClosed) {
      emit(state.copyWith(isLoading: true, error: null));
    }

    try {
      // 1. Soft-delete in Supabase
      if (AppConfig.useSupabase) {
        await Supabase.instance.client.from('inventories').update({
          'is_deleted': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', event.id);
      }

      // 2. Remove from cache
      final cacheList = _getRawCache();
      cacheList.removeWhere((item) => item['id']?.toString() == event.id);
      await _writeCache(cacheList);

      // 3. Clean up local data
      await _logService.clearLogs(inventoryId: event.id);
      await _inventoryService.deleteInventoryData(event.id);

      // 4. Emit updated state
      if (!isClosed) {
        final companyId = await _getCurrentCompanyId();
        final inventories = _readCache(companyId);
        emit(state.copyWith(
          inventories: inventories,
          selectedInventoryId: state.selectedInventoryId == event.id
              ? (inventories.isNotEmpty ? inventories.first.id : null)
              : state.selectedInventoryId,
          isLoading: false,
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
          isLoading: false,
          error: 'Failed to delete: $e',
        ));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SELECT: Update selected inventory in state
  // ═══════════════════════════════════════════════════════════════

  void _onSelect(SelectInventory event, Emitter<InventoryListState> emit) {
    String? name;
    final cacheList = _getRawCache();
    for (final item in cacheList) {
      if (item['id']?.toString() == event.id) {
        name = item['name']?.toString();
        break;
      }
    }
    emit(state.copyWith(
      selectedInventoryId: event.id,
      selectedInventoryName: name,
    ));
  }

  // ═══════════════════════════════════════════════════════════════
  // BACKGROUND SYNC: Silently refresh cache from Supabase
  // ═══════════════════════════════════════════════════════════════

  Future<void> _backgroundSync(String companyId) async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      final freshData = await _fetchFromSupabase(companyId);
      if (freshData.isNotEmpty) {
        await _writeCache(freshData);
      }
    } catch (_) {
      // Silent - background sync failure is not critical
    }
  }
}