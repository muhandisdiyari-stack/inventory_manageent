import 'package:flutter/material.dart';
import '../services/inventory_service.dart';
import '../../../core/utils/inventory_date_formatter.dart';

class LabelListWidget extends StatelessWidget {
  final List<String> labels;
  final String? currentLabel;
  final TextEditingController searchController;
  final Function(String) onSelectLabel;
  final Function(String) onRenameLabel;
  final Function(String) onDeleteLabel;
  final LabelSortType sortType;
  final Function(LabelSortType) onSortChanged;
  final InventoryService? inventoryService;

  const LabelListWidget({
    super.key,
    required this.labels,
    required this.currentLabel,
    required this.searchController,
    required this.onSelectLabel,
    required this.onRenameLabel,
    required this.onDeleteLabel,
    this.sortType = LabelSortType.nameAsc,
    required this.onSortChanged,
    this.inventoryService,
  });

  @override
  Widget build(BuildContext context) {
    final searchQuery = searchController.text.toLowerCase().trim();

    final filteredLabels = searchQuery.isEmpty
        ? labels
        : labels.where((l) => l.toLowerCase().contains(searchQuery)).toList();

    return Column(
      children: [
        // Sort dropdown
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.sort, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<LabelSortType>(
                    value: sortType,
                    isDense: true,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: LabelSortType.nameAsc,
                        child: Text('Name A-Z'),
                      ),
                      DropdownMenuItem(
                        value: LabelSortType.nameDesc,
                        child: Text('Name Z-A'),
                      ),
                      DropdownMenuItem(
                        value: LabelSortType.dateCreatedDesc,
                        child: Text('Newest First'),
                      ),
                      DropdownMenuItem(
                        value: LabelSortType.dateCreatedAsc,
                        child: Text('Oldest First'),
                      ),
                      DropdownMenuItem(
                        value: LabelSortType.dateModifiedDesc,
                        child: Text('Recently Modified'),
                      ),
                      DropdownMenuItem(
                        value: LabelSortType.dateModifiedAsc,
                        child: Text('Least Modified'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) onSortChanged(value);
                    },
                  ),
                ),
              ),
              Text(
                '${filteredLabels.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Labels list
        Expanded(
          child: labels.isEmpty
              ? _buildEmptyState(context)
              : filteredLabels.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off,
                              size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            'No labels match "$searchQuery"',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      itemCount: filteredLabels.length,
                      itemBuilder: (context, index) {
                        final label = filteredLabels[index];
                        return _buildLabelTile(context, label);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildLabelTile(BuildContext context, String label) {
    final isSelected = label == currentLabel;
    final labelInfo = inventoryService?.getLabelByName(label);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: isSelected ? colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSelectLabel(label),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.2)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.label,
                  size: 20,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                        color: isSelected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (labelInfo != null)
                      Text(
                        'Created ${InventoryDateFormatter.format(labelInfo.createdAt)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.6)
                              : Colors.grey[500],
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      onRenameLabel(label);
                      break;
                    case 'delete':
                      onDeleteLabel(label);
                      break;
                  }
                },
                icon: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer.withValues(alpha: 0.6)
                      : Colors.grey[500],
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Rename'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.label_off, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'No labels yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap + to create your first label',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}