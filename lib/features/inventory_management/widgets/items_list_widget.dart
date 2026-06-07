import 'package:flutter/material.dart';
import '../models/inventory_item.dart';

class ItemsListWidget extends StatelessWidget {
  final List<InventoryItem> items;
  final String label;
  final TextEditingController searchController;   // kept for external use, but not used internally
  final Function(InventoryItem, int) onAdjustQuantity;
  final Function(InventoryItem) onDeleteItem;
  final VoidCallback onAddItem;
  final Function(InventoryItem) onEditItem;
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;
  final Future<void> Function()? onRefresh;

  const ItemsListWidget({
    super.key,
    required this.items,
    required this.label,
    required this.searchController,
    required this.onAdjustQuantity,
    required this.onDeleteItem,
    required this.onAddItem,
    required this.onEditItem,
    this.canCreate = true,
    this.canUpdate = true,
    this.canDelete = false,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // Remove duplicate search bar – parent already provides one

    // Remove duplicates by ID before sorting
    final seenIds = <String>{};
    final uniqueItems = items.where((item) => seenIds.add(item.id)).toList();

    final sortedItems = List<InventoryItem>.from(uniqueItems)
      ..sort((a, b) {
        if (a.isExpired && !b.isExpired) return -1;
        if (!a.isExpired && b.isExpired) return 1;
        if (a.isExpiringSoon && !b.isExpiringSoon) return -1;
        if (!a.isExpiringSoon && b.isExpiringSoon) return 1;
        return a.name.compareTo(b.name);
      });

    if (items.isEmpty) return _buildEmptyState(context);

    return Expanded(
      child: sortedItems.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text('No items match your search',
                    style: TextStyle(color: Colors.grey[600])),
              ]))
          : _buildRefreshableList(sortedItems, context),
    );
  }

  Widget _buildRefreshableList(
      List<InventoryItem> sortedItems, BuildContext context) {
    final listView = ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
      itemCount: sortedItems.length,
      itemBuilder: (context, index) {
        final item = sortedItems[index];
        return _ItemCard(
          key: ValueKey(item.id),
          item: item,
          canUpdate: canUpdate,
          canDelete: canDelete,
          onIncrement: () => onAdjustQuantity(item, 1),
          onDecrement: () => onAdjustQuantity(item, -1),
          onDelete: () => onDeleteItem(item),
          onEdit: () => onEditItem(item),
        );
      },
    );

    if (onRefresh != null) {
      return RefreshIndicator(onRefresh: onRefresh!, child: listView);
    }
    return listView;
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: RefreshIndicator(
        onRefresh: onRefresh ?? () async {},
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No items in $label',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Text(canCreate ? 'Tap + to add items' : 'No items yet',
                      style: TextStyle(color: Colors.grey[500])),
                  const SizedBox(height: 16),
                  Text('Pull down to refresh',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatefulWidget {
  final InventoryItem item;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _ItemCard({
    super.key,
    required this.item,
    required this.canUpdate,
    required this.canDelete,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _isUpdating = false;

  void _handleIncrement() {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);
    widget.onIncrement();
    Future.microtask(() {
      if (mounted) setState(() => _isUpdating = false);
    });
  }

  void _handleDecrement() {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);
    widget.onDecrement();
    Future.microtask(() {
      if (mounted) setState(() => _isUpdating = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: widget.item.isExpired
              ? Colors.red.shade100
              : widget.item.isExpiringSoon
                  ? Colors.orange.shade100
                  : colorScheme.primaryContainer,
          child: Text(widget.item.quantity.toString(),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: widget.item.isExpired
                      ? Colors.red
                      : widget.item.isExpiringSoon
                          ? Colors.orange
                          : colorScheme.primary)),
        ),
        title: Row(children: [
          Expanded(
              child: Text(widget.item.displayName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          if (widget.item.isExpired) _badge('EXPIRED', Colors.red),
          if (widget.item.isExpiringSoon) _badge('EXPIRING', Colors.orange),
        ]),
        subtitle: Row(children: [
          if (widget.item.barcode.isNotEmpty) ...[
            const Icon(Icons.qr_code, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Flexible(
                child: Text(widget.item.barcode,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
          ],
          if (widget.item.size.isNotEmpty)
            Flexible(
                child: Text('Size: ${widget.item.size}',
                    style: const TextStyle(fontSize: 11))),
        ]),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '📅 Created: ${_fmt(widget.item.createdAt)}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            Text(
                                '✏️ Modified: ${_fmt(widget.item.modified)}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            Text('👤 ${widget.item.creatorDisplayName}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            if (widget.item.updatedByName != null &&
                                widget.item.updatedByName !=
                                    widget.item.createdByName)
                              Text(
                                  '👤 Updated by: ${widget.item.updaterDisplayName}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                          ])),
                  if (widget.item.color.isNotEmpty)
                    _infoRow('Color', widget.item.color),
                  if (widget.item.material.isNotEmpty)
                    _infoRow('Material', widget.item.material),
                  if (widget.item.productionDate != null)
                    _infoRow('Production',
                        widget.item.productionDate.toString().split(' ')[0]),
                  if (widget.item.expireDate != null)
                    _infoRow('Expires',
                        widget.item.expireDate.toString().split(' ')[0]),
                  if (widget.item.note.isNotEmpty)
                    _infoRow('Note', widget.item.note),
                  ...widget.item.userCustomFields.entries
                      .map((e) => _infoRow(e.key, e.value)),
                  const Divider(height: 24),
                  if (widget.canUpdate)
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton.filled(
                              onPressed: (widget.item.quantity > 0 &&
                                      !_isUpdating)
                                  ? _handleDecrement
                                  : null,
                              icon: const Icon(Icons.remove),
                              style: IconButton.styleFrom(
                                  backgroundColor:
                                      colorScheme.errorContainer,
                                  foregroundColor: colorScheme.error)),
                          Text('${widget.item.quantity}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          IconButton.filled(
                              onPressed: (widget.item.quantity <
                                          InventoryItem.maxQuantity &&
                                      !_isUpdating)
                                  ? _handleIncrement
                                  : null,
                              icon: const Icon(Icons.add),
                              style: IconButton.styleFrom(
                                  backgroundColor:
                                      colorScheme.primaryContainer,
                                  foregroundColor: colorScheme.primary)),
                          IconButton(
                              onPressed: widget.onEdit,
                              icon: const Icon(Icons.edit),
                              tooltip: 'Edit item'),
                          if (widget.canDelete)
                            IconButton(
                                onPressed: widget.onDelete,
                                icon: const Icon(Icons.delete_outline),
                                color: Colors.red,
                                tooltip: 'Delete item'),
                        ])
                  else
                    Center(
                        child: Text('View only',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]))),
                ]),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.w700)));

  Widget _infoRow(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 100,
            child: Text('$label: ',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12))),
        Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12))),
      ]));

  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}