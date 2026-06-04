part of 'inventory_bloc.dart';

class InventoryState {
  final String? inventoryId;
  final String? inventoryName;
  final List<String> labels;
  final LabelSortType sortType;
  final String? selectedLabel;
  final List<InventoryItem> currentItems;
  final List<InventoryItem> allItems;
  final InventorySettings? settings;
  final List<Map<String, dynamic>> searchResults;
  final bool isLoading;
  final bool isInitialized;
  final String? error;

  const InventoryState({
    this.inventoryId,
    this.inventoryName,
    this.labels = const [],
    this.sortType = LabelSortType.nameAsc,
    this.selectedLabel,
    this.currentItems = const [],
    this.allItems = const [],
    this.settings,
    this.searchResults = const [],
    this.isLoading = false,
    this.isInitialized = false,
    this.error,
  });

  InventoryState copyWith({
    String? inventoryId,
    String? inventoryName,
    List<String>? labels,
    LabelSortType? sortType,
    String? selectedLabel,
    List<InventoryItem>? currentItems,
    List<InventoryItem>? allItems,
    InventorySettings? settings,
    List<Map<String, dynamic>>? searchResults,
    bool? isLoading,
    bool? isInitialized,
    String? error,
  }) {
    return InventoryState(
      inventoryId: inventoryId ?? this.inventoryId,
      inventoryName: inventoryName ?? this.inventoryName,
      labels: labels ?? this.labels,
      sortType: sortType ?? this.sortType,
      selectedLabel: selectedLabel ?? this.selectedLabel,
      currentItems: currentItems ?? this.currentItems,
      allItems: allItems ?? this.allItems,
      settings: settings ?? this.settings,
      searchResults: searchResults ?? this.searchResults,
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      error: error,
    );
  }

  bool get hasLabels => labels.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryState &&
          inventoryId == other.inventoryId &&
          inventoryName == other.inventoryName &&
          sortType == other.sortType &&
          selectedLabel == other.selectedLabel &&
          isLoading == other.isLoading &&
          isInitialized == other.isInitialized &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
        inventoryId,
        inventoryName,
        sortType,
        selectedLabel,
        isLoading,
        isInitialized,
        error,
      );
}