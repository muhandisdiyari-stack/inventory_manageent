part of 'inventory_bloc.dart';

sealed class InventoryEvent {
  const InventoryEvent();
}

class InitializeInventory extends InventoryEvent {
  final String inventoryId;
  const InitializeInventory(this.inventoryId);
}

class LoadLabels extends InventoryEvent {
  const LoadLabels();
}

class CreateLabel extends InventoryEvent {
  final String name;
  const CreateLabel(this.name);
}

class RenameLabel extends InventoryEvent {
  final String oldName;
  final String newName;
  const RenameLabel(this.oldName, this.newName);
}

class DeleteLabel extends InventoryEvent {
  final String name;
  const DeleteLabel(this.name);
}

class LoadItems extends InventoryEvent {
  final String label;
  const LoadItems(this.label);
}

class SaveItem extends InventoryEvent {
  final InventoryItem item;
  const SaveItem(this.item);
}

class DeleteItem extends InventoryEvent {
  final InventoryItem item;
  const DeleteItem(this.item);
}

class AdjustQuantity extends InventoryEvent {
  final InventoryItem item;
  final int delta;
  const AdjustQuantity(this.item, this.delta);
}

class UpdateSettings extends InventoryEvent {
  final InventorySettings settings;
  const UpdateSettings(this.settings);
}

class SearchItems extends InventoryEvent {
  final String query;
  const SearchItems(this.query);
}

class ImportItems extends InventoryEvent {
  final String label;
  final List<InventoryItem> items;
  const ImportItems(this.label, this.items);
}

class SelectLabel extends InventoryEvent {
  final String? label;
  const SelectLabel(this.label);
}

class SetLabelSortType extends InventoryEvent {
  final LabelSortType sortType;
  const SetLabelSortType(this.sortType);
}

class LoadAllItems extends InventoryEvent {
  final String inventoryId;
  const LoadAllItems(this.inventoryId);
}

class RealtimeItemsChanged extends InventoryEvent {
  const RealtimeItemsChanged();
}

class RealtimeLabelsChanged extends InventoryEvent {
  const RealtimeLabelsChanged();
}

// ✅ FIX: Added missing event class
class ClearInventoryError extends InventoryEvent {
  const ClearInventoryError();
}