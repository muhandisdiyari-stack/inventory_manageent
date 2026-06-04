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
    on<ClearSelection>(_onClearSelection);
  }

  Future<String?> _getCurrentCompanyId() async {
    return await _inventoryService.getCurrentCompanyId();
  }

  List<InventoryListItem> _readCache(String? companyId) {
    final items = <InventoryListItem>[];
    final raw = _cacheBox.get('cached_inventories');
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final itemCompanyId = map['company_id']?.toString() ?? '';
          if (companyId != null && itemCompanyId == companyId) {
            items.add(InventoryListItem.fromMap(map['id']?.toString() ?? '', map));
          }
        }
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<void> _writeCache(List<Map<String, dynamic>> data) async {
    await _cacheBox.put('cached_inventories', data);
  }

  List<Map<String, dynamic>> _getRawCache() {
    final raw = _cacheBox.get('cached_inventories');
    if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return [];
  }

  Future<List<Map<String, dynamic>>> _fetchFromSupabase(String companyId) async {
    try {
      final data = await Supabase.instance.client.rpc('get_company_inventories', params: {'p_company_id': companyId});
      if (data is List) return data.map((inv) => Map<String, dynamic>.from(inv as Map)).toList();
      return [];
    } catch (e) {
      debugPrint('❌ Failed to fetch inventories: $e');
      return [];
    }
  }

  Future<void> _onLoad(LoadInventories event, Emitter<InventoryListState> emit) async {
    final companyId = await _getCurrentCompanyId();
    if (companyId == null) {
      emit(state.copyWith(inventories: [], isLoading: false, isInitialized: true, error: 'No company assigned.'));
      return;
    }
    final cached = _readCache(companyId);
    if (cached.isNotEmpty) {
      emit(state.copyWith(inventories: cached, isLoading: false, isInitialized: true, isOffline: false, isCacheOnly: true));
    } else {
      emit(state.copyWith(isLoading: true));
    }
    if (AppConfig.useSupabase) {
      try {
        final freshData = await _fetchFromSupabase(companyId);
        if (freshData.isNotEmpty) await _writeCache(freshData);
        for (final inv in freshData) {
          final id = inv['id']?.toString() ?? '';
          if (id.isNotEmpty) {
            try { await _inventoryService.initializeForInventory(id); } catch (e) { debugPrint('⚠️ Failed to init inventory $id: $e'); }
          }
        }
        final items = _readCache(companyId);
        if (!isClosed) emit(state.copyWith(inventories: items, isLoading: false, isOffline: false, isInitialized: true, isCacheOnly: false));
      } catch (e) {
        if (!isClosed) emit(state.copyWith(inventories: cached, isLoading: false, isOffline: cached.isNotEmpty, isCacheOnly: true, error: cached.isEmpty ? 'No connection.' : null));
      }
    }
  }

  Future<void> _onRefresh(RefreshInventories event, Emitter<InventoryListState> emit) async {
    emit(state.copyWith(isLoading: true, error: null, isCacheOnly: false, successMessage: null));
    add(const LoadInventories());
  }

  Future<void> _onCreate(CreateInventory event, Emitter<InventoryListState> emit) async {
    final name = event.name.trim();
    final companyId = await _getCurrentCompanyId();
    if (!AppConfig.useSupabase || companyId == null) {
      if (!isClosed) emit(state.copyWith(error: 'Cannot create while offline or no company assigned'));
      return;
    }
    emit(state.copyWith(error: null, successMessage: null));
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final timestamp = DateTime.now();
      final userId = user?.id;
      final userName = user?.userMetadata?['display_name'] ?? user?.email ?? 'Unknown';
      final response = await Supabase.instance.client.from('inventories').insert({
        'company_id': companyId, 'name': name, 'created_by': userId, 'created_by_name': userName,
        'created_at': timestamp.toUtc().toIso8601String(), 'updated_at': timestamp.toUtc().toIso8601String(),
      }).select();
      if (response.isEmpty) {
        if (!isClosed) emit(state.copyWith(error: 'Failed to create inventory - no response from server'));
        return;
      }
      final created = Map<String, dynamic>.from(response.first as Map);
      final newId = created['id']?.toString() ?? '';
      final cacheList = _getRawCache();
      cacheList.add(created);
      await _writeCache(cacheList);
      try { await _inventoryService.initializeForInventory(newId); } catch (e) { debugPrint('⚠️ Failed to init new inventory: $e'); }
      await _logService.addLog(ActivityLogEntry(id: const Uuid().v4(), timestamp: timestamp, action: 'created', entityType: 'inventory', entityName: name, inventoryId: newId, inventoryName: name, details: 'Created: "$name"'));
      if (!isClosed) {
        final items = _readCache(companyId);
        emit(state.copyWith(inventories: items, isCacheOnly: false, successMessage: 'Inventory "$name" created!'));
      }
    } catch (e) {
      if (!isClosed) emit(state.copyWith(error: 'Failed to create inventory: $e'));
    }
  }

  Future<void> _onRename(RenameInventory event, Emitter<InventoryListState> emit) async {
    try {
      if (AppConfig.useSupabase) {
        await Supabase.instance.client.from('inventories').update({'name': event.newName.trim(), 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', event.id);
      }
      final cacheList = _getRawCache();
      for (final item in cacheList) { if (item['id']?.toString() == event.id) { item['name'] = event.newName.trim(); break; } }
      await _writeCache(cacheList);
      if (!isClosed) { final companyId = await _getCurrentCompanyId(); emit(state.copyWith(inventories: _readCache(companyId))); }
    } catch (e) { if (!isClosed) emit(state.copyWith(error: 'Failed to rename: $e')); }
  }

  Future<void> _onDelete(DeleteInventory event, Emitter<InventoryListState> emit) async {
    if (!isClosed) emit(state.copyWith(isLoading: true, error: null));
    try {
      if (AppConfig.useSupabase) {
        await Supabase.instance.client.from('inventories').update({'is_deleted': true, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', event.id);
      }
      final cacheList = _getRawCache();
      cacheList.removeWhere((item) => item['id']?.toString() == event.id);
      await _writeCache(cacheList);
      await _logService.clearLogs(inventoryId: event.id);
      await _inventoryService.deleteInventoryData(event.id);
      if (!isClosed) {
        final companyId = await _getCurrentCompanyId();
        final inventories = _readCache(companyId);
        emit(state.copyWith(inventories: inventories, selectedInventoryId: state.selectedInventoryId == event.id ? (inventories.isNotEmpty ? inventories.first.id : null) : state.selectedInventoryId, isLoading: false));
      }
    } catch (e) { if (!isClosed) emit(state.copyWith(isLoading: false, error: 'Failed to delete: $e')); }
  }

  void _onSelect(SelectInventory event, Emitter<InventoryListState> emit) {
    String? name;
    for (final item in _getRawCache()) { if (item['id']?.toString() == event.id) { name = item['name']?.toString(); break; } }
    emit(state.copyWith(selectedInventoryId: event.id, selectedInventoryName: name));
  }

  void _onClearSelection(ClearSelection event, Emitter<InventoryListState> emit) {
    emit(state.copyWith(selectedInventoryId: null, selectedInventoryName: null, successMessage: null));
  }
}