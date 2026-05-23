import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/inventory_list_item.dart';
import '../../inventory_management/services/inventory_service.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';
import '../../../core/constants/app_constants.dart';

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

  List<InventoryListItem> _loadFromBox() {
    final items = <InventoryListItem>[];
    for (var key in _inventoriesBox.keys) {
      final value = _inventoriesBox.get(key);
      if (value is Map) {
        final typedMap = <String, dynamic>{};
        value.forEach((k, v) => typedMap[k.toString()] = v);
        final name = typedMap['name'] as String? ?? '';
        if (name.isNotEmpty) {
          items.add(InventoryListItem.fromMap(key.toString(), typedMap));
        }
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  void _onLoad(LoadInventories event, Emitter<InventoryListState> emit) {
    try {
      final inventories = _loadFromBox();
      emit(state.copyWith(inventories: inventories, error: null));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to load inventories: $e'));
    }
  }

  Future<void> _onCreate(CreateInventory event, Emitter<InventoryListState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final id = _uuid.v4();
      final timestamp = DateTime.now();
      await _inventoriesBox.put(id, {
        'name': event.name.trim(),
        'created': timestamp.toIso8601String(),
        'modified': timestamp.toIso8601String(),
      });
      await _inventoryService.initializeForInventory(id);
      await _logService.addLog(ActivityLogEntry(
        id: _uuid.v4(),
        timestamp: timestamp,
        action: 'created',
        entityType: 'inventory',
        entityName: event.name.trim(),
        inventoryId: id,
        inventoryName: event.name.trim(),
        details: 'Inventory created: "${event.name.trim()}"',
      ));
      final inventories = _loadFromBox();
      emit(state.copyWith(
        inventories: inventories,
        selectedInventoryId: id,
        selectedInventoryName: event.name.trim(),
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: 'Failed to create inventory: $e'));
    }
  }

  Future<void> _onRename(RenameInventory event, Emitter<InventoryListState> emit) async {
    try {
      final data = _inventoriesBox.get(event.id);
      if (data is Map) {
        final typedMap = <String, dynamic>{};
        data.forEach((k, v) => typedMap[k.toString()] = v);
        final oldName = typedMap['name'] as String? ?? '';
        typedMap['name'] = event.newName.trim();
        typedMap['modified'] = DateTime.now().toIso8601String();
        await _inventoriesBox.put(event.id, typedMap);
        await _logService.addLog(ActivityLogEntry(
          id: _uuid.v4(),
          timestamp: DateTime.now(),
          action: 'modified',
          entityType: 'inventory',
          entityName: event.newName.trim(),
          inventoryId: event.id,
          inventoryName: event.newName.trim(),
          details: 'Inventory renamed',
          changes: {'name': FieldChange(oldValue: oldName, newValue: event.newName.trim())},
        ));
        final inventories = _loadFromBox();
        emit(state.copyWith(inventories: inventories));
      }
    } catch (e) {
      emit(state.copyWith(error: 'Failed to rename: $e'));
    }
  }

  Future<void> _onDelete(DeleteInventory event, Emitter<InventoryListState> emit) async {
    try {
      final data = _inventoriesBox.get(event.id);
      final inventoryName = data is Map ? (data['name'] as String? ?? '') : '';
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
      await _logService.clearLogs(inventoryId: event.id);
      await _inventoryService.deleteInventoryData(event.id);
      await _inventoriesBox.delete(event.id);
      final inventories = _loadFromBox();
      final newSelectedId = state.selectedInventoryId == event.id
          ? (inventories.isNotEmpty ? inventories.first.id : null)
          : state.selectedInventoryId;
      emit(state.copyWith(
        inventories: inventories,
        selectedInventoryId: newSelectedId,
      ));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to delete: $e'));
    }
  }

  void _onSelect(SelectInventory event, Emitter<InventoryListState> emit) {
    String? name;
    final data = _inventoriesBox.get(event.id);
    if (data is Map) {
      final typedMap = <String, dynamic>{};
      data.forEach((k, v) => typedMap[k.toString()] = v);
      name = typedMap['name'] as String?;
    }
    emit(state.copyWith(
      selectedInventoryId: event.id,
      selectedInventoryName: name,
    ));
  }
}