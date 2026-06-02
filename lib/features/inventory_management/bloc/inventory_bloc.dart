// ignore_for_file: unused_field
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
  final ActivityLogService _logService;
  final SupabaseRealtimeService _realtimeService;

  InventoryBloc({
    required InventoryService inventoryService,
    required ActivityLogService logService,
    required SupabaseRealtimeService realtimeService,
  })  : _inventoryService = inventoryService,
        _logService = logService,
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

  String? _currentSubscribedInventory;
  Timer? _realtimeDebounce;
  static const _realtimeDebounceDuration = Duration(milliseconds: 500);

  // ═══════════════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════════════

  List<InventoryItem> _getCurrentItems() {
    if (state.selectedLabel == null) return [];
    return _inventoryService.getItemsByLabel(state.selectedLabel!);
  }

  List<String> _getCurrentLabels() {
    return _inventoryService.getSortedLabelNames(sortType: state.sortType);
  }

  // ═══════════════════════════════════════════════════════════════
  // Initialize
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onInitialize(
      InitializeInventory event, Emitter<InventoryState> emit) async {
    // Prevent duplicate initialization for the same inventory
    if (state.inventoryId == event.inventoryId && state.isInitialized) {
      return;
    }

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
          selectedLabel: labelNames.first,
          currentItems: items,
        ));
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

    _realtimeService.subscribeToInventoryItems(
      inventoryId,
      onChange: () => add(const RealtimeItemsChanged()),
    );

    _realtimeService.subscribeToLabels(
      inventoryId,
      onChange: () => add(const RealtimeLabelsChanged()),
    );
  }

  void _onLoadLabels(LoadLabels event, Emitter<InventoryState> emit) {
    final sortedLabels = _getCurrentLabels();
    emit(state.copyWith(labels: sortedLabels));
  }

  // ═══════════════════════════════════════════════════════════════
  // Label CRUD - Optimistic with background sync
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onCreateLabel(
      CreateLabel event, Emitter<InventoryState> emit) async {
    // Validate first
    if (event.name.trim().isEmpty) {
      emit(state.copyWith(error: 'Label name cannot be empty'));
      return;
    }
    if (event.name.trim().length < 2) {
      emit(state.copyWith(error: 'Label name must be at least 2 characters'));
      return;
    }

    // Optimistic UI update
    final newLabels = List<String>.from(state.labels);
    if (!newLabels.contains(event.name)) {
      newLabels.add(event.name);
      newLabels.sort();
    }
    emit(state.copyWith(
      labels: newLabels,
      selectedLabel: event.name,
      currentItems: [],
    ));

    // Background sync
    try {
      await _inventoryService.createLabel(event.name);
      final sortedLabels = _getCurrentLabels();
      emit(state.copyWith(labels: sortedLabels));
    } catch (e) {
      emit(state.copyWith(
        labels: _getCurrentLabels(),
        error: 'Failed to create label: $e',
      ));
    }
  }

  Future<void> _onRenameLabel(
      RenameLabel event, Emitter<InventoryState> emit) async {
    if (event.oldName == event.newName) return;
    if (event.newName.trim().isEmpty) {
      emit(state.copyWith(error: 'Label name cannot be empty'));
      return;
    }

    // Optimistic UI update
    final newLabels = state.labels
        .map((l) => l == event.oldName ? event.newName : l)
        .toList();
    final newSelectedLabel = state.selectedLabel == event.oldName
        ? event.newName
        : state.selectedLabel;

    List<InventoryItem> items = state.currentItems;
    if (state.selectedLabel == event.oldName) {
      items = items.map((item) {
        if (item.label == event.oldName) {
          item.label = event.newName;
        }
        return item;
      }).toList();
    }

    emit(state.copyWith(
      labels: newLabels,
      selectedLabel: newSelectedLabel,
      currentItems: items,
    ));

    // Background sync
    try {
      await _inventoryService.renameLabel(event.oldName, event.newName);
      emit(state.copyWith(labels: _getCurrentLabels()));
    } catch (e) {
      emit(state.copyWith(
        labels: _getCurrentLabels(),
        error: 'Failed to rename label: $e',
      ));
    }
  }

  Future<void> _onDeleteLabel(
      DeleteLabel event, Emitter<InventoryState> emit) async {
    // Optimistic UI update
    final newLabels = state.labels.where((l) => l != event.name).toList();
    final newSelectedLabel = state.selectedLabel == event.name
        ? (newLabels.isNotEmpty ? newLabels.first : null)
        : state.selectedLabel;

    emit(state.copyWith(
      labels: newLabels,
      selectedLabel: newSelectedLabel,
      currentItems: newSelectedLabel != null
          ? _inventoryService.getItemsByLabel(newSelectedLabel)
          : [],
    ));

    // Background sync
    try {
      await _inventoryService.deleteLabel(event.name);
      emit(state.copyWith(labels: _getCurrentLabels()));
    } catch (e) {
      emit(state.copyWith(
        labels: _getCurrentLabels(),
        error: 'Failed to delete label: $e',
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Item CRUD - Optimistic with background sync
  // ═══════════════════════════════════════════════════════════════

  void _onLoadItems(LoadItems event, Emitter<InventoryState> emit) {
    final items = _inventoryService.getItemsByLabel(event.label);
    emit(state.copyWith(selectedLabel: event.label, currentItems: items));
  }

  Future<void> _onSaveItem(
      SaveItem event, Emitter<InventoryState> emit) async {
    if (state.selectedLabel == null) return;

    // Validate item
    if (event.item.name.trim().isEmpty) {
      emit(state.copyWith(error: 'Item name cannot be empty'));
      return;
    }

    // Optimistic UI update
    final items = List<InventoryItem>.from(state.currentItems);
    final existingIndex = items.indexWhere((i) => i.id == event.item.id);
    if (existingIndex >= 0) {
      items[existingIndex] = event.item;
    } else {
      items.insert(0, event.item);
    }
    emit(state.copyWith(currentItems: items));

    // Background sync
    try {
      await _inventoryService.saveItem(event.item);
      final refreshedItems = _getCurrentItems();
      emit(state.copyWith(currentItems: refreshedItems));
      add(const LoadLabels());
    } catch (e) {
      emit(state.copyWith(
        currentItems: _getCurrentItems(),
        error: 'Failed to save item: $e',
      ));
    }
  }

  Future<void> _onDeleteItem(
      DeleteItem event, Emitter<InventoryState> emit) async {
    // Optimistic UI update
    final items =
        state.currentItems.where((i) => i.id != event.item.id).toList();
    emit(state.copyWith(currentItems: items));

    // Background sync
    try {
      event.item.customFields['is_deleted'] = 'true';
      await _inventoryService.saveItem(event.item);
      await event.item.delete();
      final refreshedItems = _getCurrentItems();
      emit(state.copyWith(currentItems: refreshedItems));
    } catch (e) {
      emit(state.copyWith(
        currentItems: _getCurrentItems(),
        error: 'Failed to delete item: $e',
      ));
    }
  }

  Future<void> _onAdjustQuantity(
      AdjustQuantity event, Emitter<InventoryState> emit) async {
    final newQuantity =
        (event.item.quantity + event.delta).clamp(0, InventoryItem.maxQuantity);
    if (newQuantity == event.item.quantity) return;

    // Optimistic UI update with cloned item
    final items = List<InventoryItem>.from(state.currentItems);
    final index = items.indexWhere((i) => i.id == event.item.id);
    if (index >= 0) {
      items[index] = InventoryItem(
        id: event.item.id,
        name: event.item.name,
        code: event.item.code,
        barcode: event.item.barcode,
        color: event.item.color,
        material: event.item.material,
        size: event.item.size,
        quantity: newQuantity,
        note: event.item.note,
        label: event.item.label,
        customFields: Map<String, String>.from(event.item.customFields),
        productionDate: event.item.productionDate,
        expireDate: event.item.expireDate,
        modified: DateTime.now(),
        createdAt: event.item.createdAt,
        createdBy: event.item.createdBy,
        createdByName: event.item.createdByName,
        isSynced: false,
      );
    }
    emit(state.copyWith(currentItems: items));

    // Update actual object and sync
    event.item.quantity = newQuantity;
    event.item.modified = DateTime.now();
    event.item.isSynced = false;

    try {
      await _inventoryService.saveItem(event.item);
      final refreshedItems = _getCurrentItems();
      emit(state.copyWith(currentItems: refreshedItems));
    } catch (e) {
      emit(state.copyWith(
        currentItems: _getCurrentItems(),
        error: 'Failed to update quantity: $e',
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Bulk Import
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onImport(
      ImportItems event, Emitter<InventoryState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _inventoryService.importItems(event.label, event.items);
      final labelNames = _getCurrentLabels();
      final items = _getCurrentItems();
      emit(state.copyWith(
        labels: labelNames,
        currentItems: items,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Import failed: $e',
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Realtime Handlers - Debounced to prevent flooding
  // ═══════════════════════════════════════════════════════════════

  void _onRealtimeItemsChanged(
      RealtimeItemsChanged event, Emitter<InventoryState> emit) {
    // Cancel any pending debounce
    _realtimeDebounce?.cancel();

    // Debounce: only sync after no new events for 500ms
    _realtimeDebounce = Timer(_realtimeDebounceDuration, () async {
      debugPrint('🔄 RealtimeItemsChanged triggered (debounced)');
      if (state.inventoryId != null) {
        try {
          // Use lightweight sync instead of full initialization
          await _inventoryService.syncItemsFromRealtime(state.inventoryId!);
        } catch (e) {
          debugPrint('⚠️ Realtime items sync failed: $e');
        }
        if (state.selectedLabel != null && !isClosed) {
          final items =
              _inventoryService.getItemsByLabel(state.selectedLabel!);
          emit(state.copyWith(currentItems: items));
        }
      }
    });
  }

  void _onRealtimeLabelsChanged(
      RealtimeLabelsChanged event, Emitter<InventoryState> emit) {
    _realtimeDebounce?.cancel();

    _realtimeDebounce = Timer(_realtimeDebounceDuration, () async {
      debugPrint('🔄 RealtimeLabelsChanged triggered (debounced)');
      if (state.inventoryId != null) {
        try {
          await _inventoryService.syncLabelsFromSupabase(state.inventoryId!);
        } catch (e) {
          debugPrint('⚠️ Realtime labels sync failed: $e');
        }
        final sortedLabels = _getCurrentLabels();
        if (!isClosed) {
          emit(state.copyWith(labels: sortedLabels));
        }
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // Other handlers
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onUpdateSettings(
      UpdateSettings event, Emitter<InventoryState> emit) async {
    try {
      await _inventoryService.updateSettings(event.settings);
      emit(state.copyWith(settings: event.settings));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to update settings: $e'));
    }
  }

  void _onSearch(SearchItems event, Emitter<InventoryState> emit) {
    try {
      if (event.query.trim().isEmpty) {
        emit(state.copyWith(searchResults: []));
        return;
      }
      final results = _inventoryService.searchAllInventories(event.query);
      emit(state.copyWith(searchResults: results));
    } catch (e) {
      emit(state.copyWith(error: 'Search failed: $e'));
    }
  }

  void _onSelectLabel(SelectLabel event, Emitter<InventoryState> emit) {
    if (event.label != null) {
      final items = _inventoryService.getItemsByLabel(event.label!);
      emit(state.copyWith(selectedLabel: event.label, currentItems: items));
    } else {
      emit(state.copyWith(selectedLabel: null, currentItems: []));
    }
  }

  void _onSetSortType(SetLabelSortType event, Emitter<InventoryState> emit) {
    final sortedLabels =
        _inventoryService.getSortedLabelNames(sortType: event.sortType);
    emit(state.copyWith(sortType: event.sortType, labels: sortedLabels));
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
        inventoryId: event.inventoryId,
        allItems: allItems,
      ));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to load all items: $e'));
    }
  }

  void _onClearError(ClearInventoryError event, Emitter<InventoryState> emit) {
    emit(state.copyWith(error: null));
  }

  @override
  Future<void> close() {
    _realtimeDebounce?.cancel();
    if (_currentSubscribedInventory != null) {
      _realtimeService.unsubscribeFromInventory(_currentSubscribedInventory!);
    }
    return super.close();
  }
}