import 'package:flutter/material.dart';
import '../../../../core/utils/inventory_date_formatter.dart';
import '../models/inventory_list_item.dart';
import '../providers/inventory_list_provider.dart';
import '../../inventory_management/services/inventory_service.dart';
import 'rename_inventory_dialog.dart';
import 'delete_inventory_dialog.dart';

class InventoryCard extends StatelessWidget {
  final InventoryListItem inventory;
  final InventoryListProvider listProvider;
  final InventoryService service;
  final void Function(String, InventoryListProvider) onOpenInventory;

  const InventoryCard({
    super.key,
    required this.inventory,
    required this.listProvider,
    required this.service,
    required this.onOpenInventory,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = _getIconColor(colorScheme);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: InkWell(
          onTap: () => onOpenInventory(inventory.id, listProvider),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildIconContainer(iconColor),
                const SizedBox(width: 16),
                _buildInventoryInfo(context),
                _buildPopupMenu(context),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getIconColor(ColorScheme colorScheme) {
    final iconColors = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      Colors.indigo,
      Colors.teal,
    ];
    return iconColors[inventory.id.hashCode.abs() % iconColors.length];
  }

  Widget _buildIconContainer(Color iconColor) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.inventory_2_rounded,
        color: iconColor,
        size: 28,
      ),
    );
  }

  Widget _buildInventoryInfo(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            inventory.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'Created ${InventoryDateFormatter.format(inventory.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopupMenu(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) => _handleMenuAction(context, value),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit_rounded, size: 20),
            title: Text('Rename'),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_rounded, size: 20, color: Colors.red),
            title: Text('Delete', style: TextStyle(color: Colors.red)),
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.all(8.0),
        child: Icon(Icons.more_vert_rounded),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, String value) {
    switch (value) {
      case 'rename':
        RenameInventoryDialog.show(
          context,
          inventory.id,
          inventory.name,
          listProvider,
        );
        break;
      case 'delete':
        DeleteInventoryDialog.show(
          context,
          inventory.id,
          inventory.name,
          listProvider,
          service,
        );
        break;
    }
  }
}