import 'package:flutter/material.dart';
import '../services/inventory_service.dart';

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
              const Icon(Icons.sort, size: 16, color: Colors.grey),
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
                      DropdownMenuItem(value: LabelSortType.nameAsc, child: Text('Name A-Z')),
                      DropdownMenuItem(value: LabelSortType.nameDesc, child: Text('Name Z-A')),
                      DropdownMenuItem(value: LabelSortType.dateCreatedDesc, child: Text('Newest First')),
                      DropdownMenuItem(value: LabelSortType.dateCreatedAsc, child: Text('Oldest First')),
                      DropdownMenuItem(value: LabelSortType.dateModifiedDesc, child: Text('Recently Modified')),
                      DropdownMenuItem(value: LabelSortType.dateModifiedAsc, child: Text('Least Modified')),
                    ],
                    onChanged: (value) {
                      if (value != null) onSortChanged(value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Labels list
        Expanded(
          child: labels.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.label_off, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('No labels yet',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                              color: Colors.grey[700])),
                      const SizedBox(height: 4),
                      Text('Tap + to create your first label',
                          style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : filteredLabels.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text('No labels match "$searchQuery"',
                              style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      itemCount: filteredLabels.length,
                      itemBuilder: (context, index) {
                        final label = filteredLabels[index];
                        final isSelected = label == currentLabel;
                        final labelInfo = inventoryService?.getLabelInfo(label);
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          color: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: ListTile(
                            leading: Icon(
                              Icons.label,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(
                              label,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.onPrimaryContainer
                                    : null,
                              ),
                            ),
                            subtitle: labelInfo != null
                                ? Text(
                                    'Created: ${_formatDate(labelInfo.createdAt)}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                  )
                                : null,
                            selected: isSelected,
                            selectedTileColor: isSelected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onTap: () => onSelectLabel(label),
                            trailing: PopupMenuButton<String>(
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
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}