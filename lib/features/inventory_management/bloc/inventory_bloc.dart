import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/inventory_service.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import '../../../core/services/activity_log_service.dart';

part 'inventory_event.dart';
part 'inventory_state.dart';

class InventoryBloc extends Bloc<InventoryEvent, InventoryState> {
  final InventoryService _inventoryService;
  final ActivityLogService _logService;

  InventoryBloc({
    required InventoryService inventoryService,
    required ActivityLogService logService,
  })  : _inventoryService = inventoryService,
        _logService = logService,
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
  }

  Future<void> _onInitialize(
      InitializeInventory event, Emitter<InventoryState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await _inventoryService.initializeForInventory(event.inventoryId);
      final labels = _inventoryService.labels;
      final settings = _inventoryService.currentSettings;
      final inventoryName =
          _inventoryService.getInventoryName(event.inventoryId);
      emit(state.copyWith(
        inventoryId: event.inventoryId,
        inventoryName: inventoryName,
        labels: labels,
        settings: settings,
        isLoading: false,
        isInitialized: true,
        selectedLabel: labels.isNotEmpty ? labels.first : null,
      ));
      if (labels.isNotEmpty) {
        add(LoadItems(labels.first));
      }
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, error: 'Failed to initialize: $e'));
    }
  }

  void _onLoadLabels(LoadLabels event, Emitter<InventoryState> emit) {
    final sortedLabels =
        _inventoryService.getSortedLabels(sortType: state.sortType);
    emit(state.copyWith(labels: sortedLabels));
  }

  Future<void> _onCreateLabel(
      CreateLabel event, Emitter<InventoryState> emit) async {
    try {
      await _inventoryService.createLabel(event.name);
      final labels = _inventoryService.labels;
      emit(state.copyWith(labels: labels, selectedLabel: event.name));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to create label: $e'));
    }
  }

  Future<void> _onRenameLabel(
      RenameLabel event, Emitter<InventoryState> emit) async {
    try {
      await _inventoryService.renameLabel(event.oldName, event.newName);
      final labels = _inventoryService.labels;
      final newSelectedLabel = state.selectedLabel == event.oldName
          ? event.newName
          : state.selectedLabel;
      emit(state.copyWith(labels: labels, selectedLabel: newSelectedLabel));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to rename label: $e'));
    }
  }

  Future<void> _onDeleteLabel(
      DeleteLabel event, Emitter<InventoryState> emit) async {
    try {
      await _inventoryService.deleteLabel(event.name);
      final labels = _inventoryService.labels;
      final newSelectedLabel = state.selectedLabel == event.name
          ? (labels.isNotEmpty ? labels.first : null)
          : state.selectedLabel;
      emit(state.copyWith(labels: labels, selectedLabel: newSelectedLabel));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to delete label: $e'));
    }
  }

  void _onLoadItems(LoadItems event, Emitter<InventoryState> emit) {
    try {
      final items = _inventoryService.getItemsByLabel(event.label);
      emit(state.copyWith(selectedLabel: event.label, currentItems: items));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to load items: $e'));
    }
  }

  Future<void> _onSaveItem(
      SaveItem event, Emitter<InventoryState> emit) async {
    try {
      await _inventoryService.saveItem(event.item);
      if (state.selectedLabel != null) {
        add(LoadItems(state.selectedLabel!));
      }
      add(const LoadLabels());
    } catch (e) {
      emit(state.copyWith(error: 'Failed to save item: $e'));
    }
  }

  Future<void> _onDeleteItem(
      DeleteItem event, Emitter<InventoryState> emit) async {
    try {
      await event.item.delete();
      if (state.selectedLabel != null) {
        add(LoadItems(state.selectedLabel!));
      }
    } catch (e) {
      emit(state.copyWith(error: 'Failed to delete item: $e'));
    }
  }

  Future<void> _onAdjustQuantity(
      AdjustQuantity event, Emitter<InventoryState> emit) async {
    try {
      final newQuantity = (event.item.quantity + event.delta)
          .clamp(0, InventoryItem.maxQuantity);
      if (newQuantity == event.item.quantity) return;
      event.item.quantity = newQuantity;
      event.item.modified = DateTime.now();
      await event.item.save();
      if (state.selectedLabel != null) {
        add(LoadItems(state.selectedLabel!));
      }
    } catch (e) {
      emit(state.copyWith(error: 'Failed to update quantity: $e'));
    }
  }

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

  Future<void> _onImport(
      ImportItems event, Emitter<InventoryState> emit) async {
    try {
      await _inventoryService.importItems(event.label, event.items);
      final labels = _inventoryService.labels;
      emit(state.copyWith(labels: labels));
      if (state.selectedLabel != null) {
        add(LoadItems(state.selectedLabel!));
      }
    } catch (e) {
      emit(state.copyWith(error: 'Import failed: $e'));
    }
  }

  void _onSelectLabel(SelectLabel event, Emitter<InventoryState> emit) {
    if (event.label != null) {
      add(LoadItems(event.label!));
    } else {
      emit(state.copyWith(selectedLabel: null, currentItems: []));
    }
  }

  void _onSetSortType(SetLabelSortType event, Emitter<InventoryState> emit) {
    final sortedLabels =
        _inventoryService.getSortedLabels(sortType: event.sortType);
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
}