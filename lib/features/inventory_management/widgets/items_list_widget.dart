import 'package:flutter/material.dart';
import '../models/inventory_item.dart';


class ItemsListWidget extends StatelessWidget {
  final List<InventoryItem> items;
  final String label;
  final TextEditingController searchController;
  final Function(InventoryItem, int) onAdjustQuantity;
  final Function(InventoryItem) onDeleteItem;
  final VoidCallback onAddItem;
  final Function(InventoryItem) onEditItem;
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;

  const ItemsListWidget({
    super.key,
    required this.items,
    required this.label,
    required this.searchController,
    required this.onAdjustQuantity,
    required this.onDeleteItem,
    required this.onAddItem,
    required this.onEditItem,
    this.canCreate = false,
    this.canUpdate = false,
    this.canDelete = false,
  });

  @override
  Widget build(BuildContext context) {
    final searchQuery = searchController.text.toLowerCase().trim();

    final filteredItems = searchQuery.isEmpty
        ? items
        : items.where((item) => item.matchesQuery(searchQuery)).toList();

    final sortedItems = List<InventoryItem>.from(filteredItems);
    sortedItems.sort((a, b) {
      if (a.isExpired && !b.isExpired) return -1;
      if (!a.isExpired && b.isExpired) return 1;
      if (a.isExpiringSoon && !b.isExpiringSoon) return -1;
      if (!a.isExpiringSoon && b.isExpiringSoon) return 1;
      return a.name.compareTo(b.name);
    });

    if (items.isEmpty) {
      return _buildEmptyState(context);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Search items in $label...',
              prefixIcon: const Icon(Icons.search, size: 16),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () => searchController.clear(),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(40)),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        if (searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Found ${sortedItems.length} of ${items.length} items',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        Expanded(
          child: sortedItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('No items match "$searchQuery"',
                          style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
                  itemCount: sortedItems.length,
                  itemBuilder: (context, index) {
                    final item = sortedItems[index];
                    return _ItemCard(
                      item: item,
                      canUpdate: canUpdate,
                      canDelete: canDelete,
                      onIncrement: () => onAdjustQuantity(item, 1),
                      onDecrement: () => onAdjustQuantity(item, -1),
                      onDelete: () => onDeleteItem(item),
                      onEdit: () => onEditItem(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text('No items in $label',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[700])),
          const SizedBox(height: 4),
          Text(canCreate ? 'Tap + to add items' : 'No items yet',
              style: TextStyle(color: Colors.grey[500])),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final InventoryItem item;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _ItemCard({
    required this.item,
    required this.canUpdate,
    required this.canDelete,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: item.isExpired
              ? Colors.red.shade100
              : item.isExpiringSoon
                  ? Colors.orange.shade100
                  : colorScheme.primaryContainer,
          child: Text(
            item.quantity.toString(),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: item.isExpired
                  ? Colors.red
                  : item.isExpiringSoon
                      ? Colors.orange
                      : colorScheme.primary,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (item.code.isNotEmpty)
                    Text(item.code, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            if (item.isExpired)
              _buildBadge('EXPIRED', Colors.red)
            else if (item.isExpiringSoon)
              _buildBadge('EXPIRING', Colors.orange),
            if (item.hasReachedUpdateLimit)
              _buildBadge('LOCKED', Colors.purple),
          ],
        ),
        subtitle: Row(
          children: [
            if (item.barcode.isNotEmpty) ...[
              const Icon(Icons.qr_code, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              Flexible(
                child: Text(item.barcode, style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
            ],
            if (item.size.isNotEmpty)
              Flexible(
                child: Text('Size: ${item.size}', style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Creator/updater info
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📅 Created: ${item.formattedCreatedAt}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text('✏️ Modified: ${item.formattedModifiedAt}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text('👤 Created by: ${item.creatorDisplayName}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      if (item.updatedByName != null && item.updatedByName != item.createdByName)
                        Text('👤 Updated by: ${item.updaterDisplayName}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      if (item.updateCount > 0)
                        Text('🔄 Updates: ${item.updateCount}/3',
                            style: TextStyle(
                                fontSize: 11,
                                color: item.hasReachedUpdateLimit ? Colors.red : Colors.grey)),
                    ],
                  ),
                ),

                // Item details
                if (item.color.isNotEmpty) _infoRow('Color', item.color),
                if (item.material.isNotEmpty) _infoRow('Material', item.material),
                if (item.productionDate != null)
                  _infoRow('Production', item.productionDate.toString().split(' ')[0]),
                if (item.expireDate != null)
                  _infoRow('Expires', item.expireDate.toString().split(' ')[0]),
                if (item.note.isNotEmpty) _infoRow('Note', item.note),
                ...item.userCustomFields.entries.map((e) => _infoRow(e.key, e.value)),

                const Divider(height: 24),

                // Action buttons — gated by permissions
                if (canUpdate && !item.hasReachedUpdateLimit) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton.filled(
                        onPressed: item.quantity > 0 ? onDecrement : null,
                        icon: const Icon(Icons.remove),
                        tooltip: 'Decrease quantity',
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.errorContainer,
                          foregroundColor: colorScheme.error,
                        ),
                      ),
                      Text('${item.quantity}',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              )),
                      IconButton.filled(
                        onPressed: item.quantity < InventoryItem.maxQuantity ? onIncrement : null,
                        icon: const Icon(Icons.add),
                        tooltip: 'Increase quantity',
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.primary,
                        ),
                      ),
                      IconButton(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit),
                        tooltip: 'Edit item',
                      ),
                      if (canDelete)
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline),
                          color: Colors.red,
                          tooltip: 'Delete item',
                        ),
                    ],
                  ),
                ] else if (item.hasReachedUpdateLimit) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock, size: 16, color: Colors.purple),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'This item has reached the maximum update limit. Contact an admin.',
                            style: TextStyle(fontSize: 12, color: Colors.purple),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Viewer: no action buttons
                  Center(
                    child: Text(
                      'View only — contact admin for edit access',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text('$label: ',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}