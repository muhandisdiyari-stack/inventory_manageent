part of 'inventory_list_bloc.dart';

class InventoryListState {
  final List<InventoryListItem> inventories;
  final String? selectedInventoryId;
  final String? selectedInventoryName;
  final bool isLoading;
  final bool isInitialized;
  final bool isOffline;
  final bool isCacheOnly;
  final String? error;

  const InventoryListState({
    this.inventories = const [],
    this.selectedInventoryId,
    this.selectedInventoryName,
    this.isLoading = false,
    this.isInitialized = false,
    this.isOffline = false,
    this.isCacheOnly = false,
    this.error,
  });

  InventoryListState copyWith({
    List<InventoryListItem>? inventories,
    String? selectedInventoryId,
    String? selectedInventoryName,
    bool? isLoading,
    bool? isInitialized,
    bool? isOffline,
    bool? isCacheOnly,
    String? error,
  }) {
    return InventoryListState(
      inventories: inventories ?? this.inventories,
      selectedInventoryId: selectedInventoryId,
      selectedInventoryName: selectedInventoryName,
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      isOffline: isOffline ?? this.isOffline,
      isCacheOnly: isCacheOnly ?? this.isCacheOnly,
      error: error,
    );
  }

  bool get hasInventories => inventories.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryListState &&
          selectedInventoryId == other.selectedInventoryId &&
          isLoading == other.isLoading &&
          isInitialized == other.isInitialized &&
          isOffline == other.isOffline &&
          isCacheOnly == other.isCacheOnly &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
        selectedInventoryId, isLoading, isInitialized,
        isOffline, isCacheOnly, error,
      );
}