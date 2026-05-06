import 'package:flutter/material.dart';

class CreateInventoryDialog {
  static void show(
    BuildContext context,
    dynamic listProvider,
    dynamic service,
  ) {
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
          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDragHandle(context),
            const SizedBox(height: 24),
            _buildHeader(context),
            const SizedBox(height: 8),
            _buildDescription(context),
            const SizedBox(height: 20),
            _buildTextField(controller, context, listProvider, service),
            const SizedBox(height: 20),
            _buildActions(dialogContext, controller, listProvider, service),
          ],
        ),
      ),
    );
  }

  static Widget _buildDragHandle(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  static Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.add_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Create New Inventory',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }

  static Widget _buildDescription(BuildContext context) {
    return Text(
      'Give your inventory a descriptive name to easily identify it',
      style: TextStyle(
        // Fixed: Replaced withOpacity with withValues
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        fontSize: 14,
      ),
    );
  }

  static Widget _buildTextField(
    TextEditingController controller,
    BuildContext context,
    dynamic listProvider,
    dynamic service,
  ) {
    return TextField(
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
          listProvider.createInventory(value.trim(), service);
          Navigator.pop(context);
        }
      },
    );
  }

  static Widget _buildActions(
    BuildContext dialogContext,
    TextEditingController controller,
    dynamic listProvider,
    dynamic service,
  ) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
                listProvider.createInventory(name, service);
                Navigator.pop(dialogContext);
              }
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Create',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}