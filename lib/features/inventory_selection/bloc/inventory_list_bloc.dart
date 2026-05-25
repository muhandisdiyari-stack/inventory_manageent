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

  // ─── Get current company from Supabase ───────────────────────
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

  // ─── Read cache (fast, no network) ───────────────────────────
  List<InventoryListItem> _readCache(String? companyId) {
    final items = <InventoryListItem>[];
    final raw = _cacheBox.get('cached_inventories');
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final itemCompanyId =
              map['company_id']?.toString() ?? '';
          if (companyId == null ||
              itemCompanyId == companyId) {
            items.add(
                InventoryListItem.fromMap(map['id']?.toString() ?? '', map));
          }
        }
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  // ─── Write cache (after Supabase success) ────────────────────
  Future<void> _writeCache(
      List<Map<String, dynamic>> data) async {
    await _cacheBox.put('cached_inventories', data);
  }

  // ─── Load: Try Supabase → fallback to cache ──────────────────
  Future<void> _onLoad(
      LoadInventories event,
      Emitter<InventoryListState> emit) async {
    final companyId = await _getCurrentCompanyId();

    // Show cached data immediately for fast loading
    final cached = _readCache(companyId);
    if (cached.isNotEmpty) {
      emit(state.copyWith(
        inventories: cached,
        isLoading: true,
        isOffline: false,
      ));
    } else {
      emit(state.copyWith(isLoading: true, error: null));
    }

    try {
      if (!AppConfig.useSupabase || companyId == null) {
        emit(state.copyWith(
          inventories: cached,
          isLoading: false,
          isOffline: true,
        ));
        return;
      }

      // Fetch from Supabase (source of truth)
      final data = await Supabase.instance.client
          .rpc('get_company_inventories',
              params: {'p_company_id': companyId});

      if (data is List) {
        final inventories = data
            .map((inv) => Map<String, dynamic>.from(inv as Map))
            .toList();

        // Cache the fresh data
        await _writeCache(inventories);

        // Initialize each inventory service
        for (final inv in inventories) {
          final id = inv['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            await _inventoryService.initializeForInventory(id);
          }
        }

        // Emit fresh data
        final items = _readCache(companyId);
        emit(state.copyWith(
          inventories: items,
          isLoading: false,
          isOffline: false,
          isInitialized: true,
        ));
      } else {
        emit(state.copyWith(
          inventories: cached,
          isLoading: false,
          isOffline: false,
        ));
      }
    } catch (e) {
      // Network error - show cached data
      emit(state.copyWith(
        inventories: cached,
        isLoading: false,
        isOffline: true,
        error: cached.isEmpty ? 'No connection' : null,
      ));
    }
  }

  // ─── Refresh: Force reload from Supabase ─────────────────────
  Future<void> _onRefresh(
      RefreshInventories event,
      Emitter<InventoryListState> emit) async {
    add(const LoadInventories());
  }

  // ─── Create: Supabase FIRST, then cache ──────────────────────
  Future<void> _onCreate(
      CreateInventory event,
      Emitter<InventoryListState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));

    final name = event.name.trim();
    final companyId = await _getCurrentCompanyId();

    if (!AppConfig.useSupabase || companyId == null) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Cannot create while offline',
      ));
      return;
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      final timestamp = DateTime.now();

      // 1. Insert into Supabase
      final response = await Supabase.instance.client
          .from('inventories')
          .insert({
        'company_id': companyId,
        'name': name,
        'created_by': user?.id,
        'created_by_name':
            user?.userMetadata?['display_name'] ??
                    user?.email ??
                'Unknown',
        'created_at': timestamp.toUtc().toIso8601String(),
        'updated_at': timestamp.toUtc().toIso8601String(),
      }).select();

      if (response is List && response.isNotEmpty) {
        final created = Map<String, dynamic>.from(response.first as Map);
        final id = created['id']?.toString() ?? '';

        // 2. Initialize local service
        await _inventoryService.initializeForInventory(id);

        // 3. Log
        await _logService.addLog(ActivityLogEntry(
          id: id,
          timestamp: timestamp,
          action: 'created',
          entityType: 'inventory',
          entityName: name,
          inventoryId: id,
          inventoryName: name,
          details: 'Created: "$name"',
        ));

        // 4. Reload from Supabase to update cache
        add(const LoadInventories());
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to create: $e',
      ));
    }
  }

  // ─── Rename: Supabase FIRST, then cache ──────────────────────
  Future<void> _onRename(
      RenameInventory event,
      Emitter<InventoryListState> emit) async {
    try {
      if (AppConfig.useSupabase) {
        await Supabase.instance.client
            .from('inventories')
            .update({
          'name': event.newName.trim(),
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        }).eq('id', event.id);
      }

      await _logService.addLog(ActivityLogEntry(
        id: event.id,
        timestamp: DateTime.now(),
        action: 'modified',
        entityType: 'inventory',
        entityName: event.newName.trim(),
        inventoryId: event.id,
        inventoryName: event.newName.trim(),
        details: 'Renamed to "${event.newName.trim()}"',
      ));

      // Reload to refresh cache
      add(const LoadInventories());
    } catch (e) {
      emit(state.copyWith(error: 'Failed to rename: $e'));
    }
  }

  // ─── Delete: Supabase FIRST, then cache ──────────────────────
  Future<void> _onDelete(
      DeleteInventory event,
      Emitter<InventoryListState> emit) async {
    try {
      // 1. Soft delete in Supabase
      if (AppConfig.useSupabase) {
        await Supabase.instance.client
            .from('inventories')
            .update({
          'is_deleted': true,
          'updated_at':
              DateTime.now().toUtc().toIso8601String(),
        }).eq('id', event.id);
      }

      // 2. Clean up local data
      await _logService.clearLogs(inventoryId: event.id);
      await _inventoryService.deleteInventoryData(event.id);

      // 3. Reload from Supabase to refresh cache
      add(const LoadInventories());
    } catch (e) {
      emit(state.copyWith(
          error: 'Failed to delete: $e'));
    }
  }

  // ─── Select ─────────────────────────────────────────────────
  void _onSelect(
      SelectInventory event,
      Emitter<InventoryListState> emit) {
    emit(state.copyWith(
      selectedInventoryId: event.id,
      selectedInventoryName: _getInventoryName(event.id),
    ));
  }

  String? _getInventoryName(String id) {
    final raw = _cacheBox.get('cached_inventories');
    if (raw is List) {
      for (final item in raw) {
        if (item is Map &&
            item['id']?.toString() == id) {
          return item['name']?.toString();
        }
      }
    }
    return null;
  }
}