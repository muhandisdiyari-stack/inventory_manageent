import 'package:flutter/material.dart';
import '../providers/inventory_list_provider.dart';
import '../../inventory_management/services/inventory_service.dart';

class DeleteInventoryDialog {
  static void show(
    BuildContext context,
    String id,
    String name,
    InventoryListProvider listProvider,
    InventoryService service,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.delete_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 28,
          ),
        ),
        title: const Text('Delete Inventory'),
        content: Text(
          'Are you sure you want to delete "$name"?\n\nThis action cannot be undone. All items and data in this inventory will be permanently lost.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              // Close the delete dialog first
              Navigator.pop(ctx);
              
              // Show loading indicator
              if (context.mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (loadingCtx) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              
              try {
                await listProvider.deleteInventory(id, service);
                
                // Dismiss loading dialog
                if (context.mounted) {
                  Navigator.pop(context);
                }
                
                // Show success message
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('"$name" deleted successfully'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                // Dismiss loading dialog
                if (context.mounted) {
                  Navigator.pop(context);
                }
                
                debugPrint('Error deleting inventory: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete inventory: $e'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}