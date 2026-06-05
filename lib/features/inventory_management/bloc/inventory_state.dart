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

  // Sentinel for copyWith to preserve null values
  static const _keep = Object();

  InventoryState copyWith({
    Object? inventoryId = _keep,
    Object? inventoryName = _keep,
    List<String>? labels,
    LabelSortType? sortType,
    Object? selectedLabel = _keep,
    List<InventoryItem>? currentItems,
    List<InventoryItem>? allItems,
    Object? settings = _keep,
    List<Map<String, dynamic>>? searchResults,
    bool? isLoading,
    bool? isInitialized,
    Object? error = _keep,
  }) {
    return InventoryState(
      inventoryId: inventoryId == _keep ? this.inventoryId : inventoryId as String?,
      inventoryName: inventoryName == _keep ? this.inventoryName : inventoryName as String?,
      labels: labels ?? this.labels,
      sortType: sortType ?? this.sortType,
      selectedLabel: selectedLabel == _keep ? this.selectedLabel : selectedLabel as String?,
      currentItems: currentItems ?? this.currentItems,
      allItems: allItems ?? this.allItems,
      settings: settings == _keep ? this.settings : settings as InventorySettings?,
      searchResults: searchResults ?? this.searchResults,
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      error: error == _keep ? this.error : error as String?,
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
          error == other.error &&
          _listEquals(labels, other.labels) &&
          _listEquals(currentItems, other.currentItems) &&
          _listEquals(allItems, other.allItems) &&
          _listEquals(searchResults, other.searchResults) &&
          settings == other.settings;

  @override
  int get hashCode => Object.hash(
        inventoryId, inventoryName, sortType, selectedLabel,
        isLoading, isInitialized, error, settings,
        Object.hashAll(labels),
        Object.hashAll(currentItems),
      );

  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}