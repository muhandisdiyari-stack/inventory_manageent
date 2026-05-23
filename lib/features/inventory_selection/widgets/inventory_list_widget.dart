import 'package:flutter/material.dart';
import '../../search/screens/search_screen.dart';
import 'inventory_card.dart';
import '../models/inventory_list_item.dart';

class InventoryListWidget extends StatelessWidget {
  final List<InventoryListItem> inventories;
  final void Function(String) onOpenInventory;

  const InventoryListWidget({
    super.key,
    required this.inventories,
    required this.onOpenInventory,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        _buildHeader(context),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        _buildInventorySlivers(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Row(
          children: [
            Icon(
              Icons.inventory_2_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Inventories',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    '${inventories.length} ${inventories.length == 1 ? 'inventory' : 'inventories'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Search all inventories',
              style: IconButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventorySlivers(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final inventory = inventories[index];
            return InventoryCard(
              inventory: inventory,
              onOpenInventory: onOpenInventory,
            );
          },
          childCount: inventories.length,
        ),
      ),
    );
  }
}