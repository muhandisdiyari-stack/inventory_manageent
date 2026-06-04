import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/inventory_service.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/database/supabase/supabase_realtime_service.dart';

part 'inventory_event.dart';
part 'inventory_state.dart';

class InventoryBloc extends Bloc<InventoryEvent, InventoryState> {
  final InventoryService _inventoryService;
  final SupabaseRealtimeService _realtimeService;

  Timer? _itemsDebounce;
  Timer? _labelsDebounce;
  String? _currentSubscribedInventory;
  static const _realtimeDebounceDuration = Duration(milliseconds: 800);

  InventoryBloc({
    required InventoryService inventoryService,
    required ActivityLogService logService,
    required SupabaseRealtimeService realtimeService,
  })  : _inventoryService = inventoryService,
        _realtimeService = realtimeService,
        super(const InventoryState()) {
    on<InitializeInventory>(_onInitialize);
    on<LoadLabels>(_onLoadLabels);
    on<CreateLabel>(_onCreateLabel);
    on<RenameLabel>(_onRenameLabel);
    on<DeleteLabel>(_onDeleteLabel);
    on<LoadItems>(_onLoadItems);
    on<SaveItem>(_onSaveItem);
    on<DeleteItem>(_onDeleteItem);
    on<AdjustQuantity>(_onAdjustQuantity);
    on<UpdateSettings>(_onUpdateSettings);
    on<SearchItems>(_onSearch);
    on<ImportItems>(_onImport);
    on<SelectLabel>(_onSelectLabel);
    on<SetLabelSortType>(_onSetSortType);
    on<LoadAllItems>(_onLoadAllItems);
    on<RealtimeItemsChanged>(_onRealtimeItemsChanged);
    on<RealtimeLabelsChanged>(_onRealtimeLabelsChanged);
    on<ClearInventoryError>(_onClearError);
  }

  List<InventoryItem> _getCurrentItems() {
    if (state.selectedLabel == null) return [];
    return _inventoryService.getItemsByLabel(state.selectedLabel!);
  }

  List<String> _getCurrentLabels() {
    return _inventoryService.getSortedLabelNames(sortType: state.sortType);
  }

  Future<void> _onInitialize(
      InitializeInventory event, Emitter<InventoryState> emit) async {
    if (state.inventoryId == event.inventoryId && state.isInitialized) return;
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await _inventoryService.initializeForInventory(event.inventoryId);
      final allLabels = _inventoryService.labels;
      final labelNames = allLabels.map((l) => l.name).toList();
      final settings = _inventoryService.currentSettings;
      final inventoryName =
          _inventoryService.getInventoryName(event.inventoryId);
      _setupRealtimeSubscriptions(event.inventoryId);
      emit(state.copyWith(
        inventoryId: event.inventoryId,
        inventoryName: inventoryName,
        labels: labelNames,
        settings: settings,
        isLoading: false,
        isInitialized: true,
        selectedLabel: labelNames.isNotEmpty ? labelNames.first : null,
      ));
      if (labelNames.isNotEmpty) {
        final items = _inventoryService.getItemsByLabel(labelNames.first);
        emit(state.copyWith(
            selectedLabel: labelNames.first, currentItems: items));
      }
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, error: 'Failed to initialize: $e'));
    }
  }

  void _setupRealtimeSubscriptions(String inventoryId) {
    if (_currentSubscribedInventory == inventoryId) return;
    if (_currentSubscribedInventory != null) {
      _realtimeService.unsubscribeFromInventory(_currentSubscribedInventory!);
    }
    _currentSubscribedInventory = inventoryId;
    _realtimeService.subscribeToInventoryItems(inventoryId,
        onChange: () => add(const RealtimeItemsChanged()));
    _realtimeService.subscribeToLabels(inventoryId,
        onChange: () => add(const RealtimeLabelsChanged()));
  }

  void _onLoadLabels(LoadLabels event, Emitter<InventoryState> emit) {
    emit(state.copyWith(labels: _getCurrentLabels()));
  }

  Future<void> _onCreateLabel(
      CreateLabel event, Emitter<InventoryState> emit) async {
    if (event.name.trim().isEmpty) {
      emit(state.copyWith(error: 'Label name cannot be empty'));
      return;
    }
    final newLabels = List<String>.from(state.labels);
    if (!newLabels.contains(event.name)) {
      newLabels.add(event.name);
      newLabels.sort();
    }
    emit(state.copyWith(
        labels: newLabels, selectedLabel: event.name, currentItems: []));
    try {
      await _inventoryService.createLabel(event.name);
      emit(state.copyWith(labels: _getCurrentLabels()));
    } catch (e) {
      emit(state.copyWith(labels: _getCurrentLabels(), error: 'Failed: $e'));
    }
  }

  Future<void> _onRenameLabel(
      RenameLabel event, Emitter<InventoryState> emit) async {
    if (event.oldName == event.newName) return;
    final newLabels = state.labels
        .map((l) => l == event.oldName ? event.newName : l)
        .toList();
    final newSel = state.selectedLabel == event.oldName
        ? event.newName
        : state.selectedLabel;
    List<InventoryItem> items = state.currentItems;
    if (state.selectedLabel == event.oldName) {
      items = items.map((item) {
        if (item.label == event.oldName) item.label = event.newName;
        return item;
      }).toList();
    }
    emit(state.copyWith(
        labels: newLabels, selectedLabel: newSel, currentItems: items));
    try {
      await _inventoryService.renameLabel(event.oldName, event.newName);
      emit(state.copyWith(labels: _getCurrentLabels()));
    } catch (e) {
      emit(state.copyWith(labels: _getCurrentLabels(), error: 'Failed: $e'));
    }
  }

  Future<void> _onDeleteLabel(
      DeleteLabel event, Emitter<InventoryState> emit) async {
    final newLabels = state.labels.where((l) => l != event.name).toList();
    final newSel = state.selectedLabel == event.name
        ? (newLabels.isNotEmpty ? newLabels.first : null)
        : state.selectedLabel;
    emit(state.copyWith(
      labels: newLabels,
      selectedLabel: newSel,
      currentItems:
          newSel != null ? _inventoryService.getItemsByLabel(newSel) : [],
    ));
    try {
      await _inventoryService.deleteLabel(event.name);
      emit(state.copyWith(labels: _getCurrentLabels()));
    } catch (e) {
      emit(state.copyWith(labels: _getCurrentLabels(), error: 'Failed: $e'));
    }
  }

  void _onLoadItems(LoadItems event, Emitter<InventoryState> emit) {
    emit(state.copyWith(
        selectedLabel: event.label,
        currentItems: _inventoryService.getItemsByLabel(event.label)));
  }

  Future<void> _onSaveItem(
      SaveItem event, Emitter<InventoryState> emit) async {
    if (state.selectedLabel == null) return;
    final items = List<InventoryItem>.from(state.currentItems);
    final idx = items.indexWhere((i) => i.id == event.item.id);
    if (idx >= 0) {
      items[idx] = event.item;
    } else {
      items.insert(0, event.item);
    }
    emit(state.copyWith(currentItems: items));
    try {
      await _inventoryService.saveItem(event.item);
      emit(state.copyWith(currentItems: _getCurrentItems()));
      add(const LoadLabels());
    } catch (e) {
      emit(state.copyWith(
          currentItems: _getCurrentItems(), error: 'Failed: $e'));
    }
  }

  Future<void> _onDeleteItem(
      DeleteItem event, Emitter<InventoryState> emit) async {
    final items =
        state.currentItems.where((i) => i.id != event.item.id).toList();
    emit(state.copyWith(currentItems: items));
    try {
      await _inventoryService.saveItem(event.item);
      await event.item.delete();
      emit(state.copyWith(currentItems: _getCurrentItems()));
    } catch (e) {
      emit(state.copyWith(
          currentItems: _getCurrentItems(), error: 'Failed: $e'));
    }
  }

  Future<void> _onAdjustQuantity(
      AdjustQuantity event, Emitter<InventoryState> emit) async {
    final newQuantity = (event.item.quantity + event.delta)
        .clamp(0, InventoryItem.maxQuantity);
    if (newQuantity == event.item.quantity) return;

    event.item.quantity = newQuantity;
    event.item.modified = DateTime.now();
    event.item.isSynced = false;

    final items = List<InventoryItem>.from(state.currentItems);
    final index = items.indexWhere((i) => i.id == event.item.id);
    if (index >= 0) {
      items[index] = event.item;
    }
    emit(state.copyWith(currentItems: items));

    try {
      await _inventoryService.saveItem(event.item);
      final refreshedItems = _getCurrentItems();
      if (!isClosed) emit(state.copyWith(currentItems: refreshedItems));
    } catch (e) {
      debugPrint('⚠️ Quantity sync failed: $e');
    }
  }

  Future<void> _onImport(
      ImportItems event, Emitter<InventoryState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _inventoryService.importItems(event.label, event.items);
      emit(state.copyWith(
          labels: _getCurrentLabels(),
          currentItems: _getCurrentItems(),
          isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: 'Import failed: $e'));
    }
  }

  void _onRealtimeItemsChanged(
      RealtimeItemsChanged event, Emitter<InventoryState> emit) {
    _itemsDebounce?.cancel();
    _itemsDebounce = Timer(_realtimeDebounceDuration, () async {
      if (state.inventoryId != null && !isClosed) {
        try {
          await _inventoryService.syncItemsFromRealtime(state.inventoryId!);
        } catch (_) {}
        if (state.selectedLabel != null && !isClosed) {
          emit(state.copyWith(
              currentItems:
                  _inventoryService.getItemsByLabel(state.selectedLabel!)));
        }
      }
    });
  }

  void _onRealtimeLabelsChanged(
      RealtimeLabelsChanged event, Emitter<InventoryState> emit) {
    _labelsDebounce?.cancel();
    _labelsDebounce = Timer(_realtimeDebounceDuration, () async {
      if (state.inventoryId != null && !isClosed) {
        try {
          await _inventoryService.syncLabelsFromSupabase(state.inventoryId!);
        } catch (_) {}
        if (!isClosed) emit(state.copyWith(labels: _getCurrentLabels()));
      }
    });
  }

  Future<void> _onUpdateSettings(
      UpdateSettings event, Emitter<InventoryState> emit) async {
    try {
      await _inventoryService.updateSettings(event.settings);
      emit(state.copyWith(settings: event.settings));
    } catch (e) {
      emit(state.copyWith(error: 'Failed: $e'));
    }
  }

  void _onSearch(SearchItems event, Emitter<InventoryState> emit) {
    try {
      if (event.query.trim().isEmpty) {
        emit(state.copyWith(searchResults: []));
        return;
      }
      emit(state.copyWith(
          searchResults:
              _inventoryService.searchAllInventories(event.query)));
    } catch (e) {
      emit(state.copyWith(error: 'Search failed: $e'));
    }
  }

  void _onSelectLabel(SelectLabel event, Emitter<InventoryState> emit) {
    if (event.label != null) {
      emit(state.copyWith(
          selectedLabel: event.label,
          currentItems: _inventoryService.getItemsByLabel(event.label!)));
    } else {
      emit(state.copyWith(selectedLabel: null, currentItems: []));
    }
  }

  void _onSetSortType(SetLabelSortType event, Emitter<InventoryState> emit) {
    emit(state.copyWith(
        sortType: event.sortType,
        labels: _inventoryService.getSortedLabelNames(
            sortType: event.sortType)));
  }

  Future<void> _onLoadAllItems(
      LoadAllItems event, Emitter<InventoryState> emit) async {
    try {
      if (_inventoryService.currentInventoryId != event.inventoryId) {
        await _inventoryService.initializeForInventory(event.inventoryId);
      }
      final allItemsMap = _inventoryService.getAllItems();
      final allItems = <InventoryItem>[];
      for (final entry in allItemsMap.entries) {
        allItems.addAll(entry.value);
      }
      emit(state.copyWith(
          inventoryId: event.inventoryId, allItems: allItems));
    } catch (e) {
      emit(state.copyWith(error: 'Failed: $e'));
    }
  }

  void _onClearError(ClearInventoryError event, Emitter<InventoryState> emit) {
    emit(state.copyWith(error: null));
  }

  @override
  Future<void> close() {
    _itemsDebounce?.cancel();
    _labelsDebounce?.cancel();
    if (_currentSubscribedInventory != null) {
      _realtimeService.unsubscribeFromInventory(_currentSubscribedInventory!);
    }
    return super.close();
  }
}