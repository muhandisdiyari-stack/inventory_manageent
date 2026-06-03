import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/inventory_list_bloc.dart';

class CreateInventoryDialog {
  static void show(BuildContext context) {
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (dialogContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(dialogContext).viewInsets.bottom + 28,
          left: 20, right: 20, top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Text('Create New Inventory', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Text('Give your inventory a descriptive name', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14)),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'e.g., Warehouse A, Storage Room 1',
                prefixIcon: const Icon(Icons.inventory_2_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  _createInventory(dialogContext, context, value.trim(), controller);
                }
              },
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final name = controller.text.trim();
                    if (name.isNotEmpty) {
                      _createInventory(dialogContext, context, name, controller);
                    }
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Create', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  static void _createInventory(
    BuildContext dialogContext,
    BuildContext screenContext,
    String name,
    TextEditingController controller,
  ) {
    // Dispatch to InventoryListBloc to create the inventory
    // The bloc will set selectedInventoryId after successful creation
    // The InventorySelectionScreen listener will handle auto-navigation
    screenContext.read<InventoryListBloc>().add(CreateInventory(name));

    // Pop the dialog immediately
    if (dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
  }
}