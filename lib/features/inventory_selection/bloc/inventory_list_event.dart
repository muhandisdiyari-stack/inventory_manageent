part of 'inventory_list_bloc.dart';

sealed class InventoryListEvent {
  const InventoryListEvent();
}

class LoadInventories extends InventoryListEvent {
  const LoadInventories();
}

class CreateInventory extends InventoryListEvent {
  final String name;
  const CreateInventory(this.name);
}

class RenameInventory extends InventoryListEvent {
  final String id;
  final String newName;
  const RenameInventory(this.id, this.newName);
}

class DeleteInventory extends InventoryListEvent {
  final String id;
  const DeleteInventory(this.id);
}

class SelectInventory extends InventoryListEvent {
  final String id;
  const SelectInventory(this.id);
}