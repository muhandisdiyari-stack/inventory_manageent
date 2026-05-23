part of 'inventory_list_bloc.dart';

class InventoryListState {
  final List<InventoryListItem> inventories;
  final String? selectedInventoryId;
  final String? selectedInventoryName;
  final bool isLoading;
  final String? error;

  const InventoryListState({
    this.inventories = const [],
    this.selectedInventoryId,
    this.selectedInventoryName,
    this.isLoading = false,
    this.error,
  });

  InventoryListState copyWith({
    List<InventoryListItem>? inventories,
    String? selectedInventoryId,
    String? selectedInventoryName,
    bool? isLoading,
    String? error,
  }) {
    return InventoryListState(
      inventories: inventories ?? this.inventories,
      selectedInventoryId: selectedInventoryId ?? this.selectedInventoryId,
      selectedInventoryName: selectedInventoryName ?? this.selectedInventoryName,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  bool get hasInventories => inventories.isNotEmpty;
}