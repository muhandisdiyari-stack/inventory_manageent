import 'package:flutter/material.dart';

class LabelListWidget extends StatelessWidget {
  final List<String> labels;
  final String? currentLabel;
  final TextEditingController searchController;
  final Function(String) onSelectLabel;
  final Function(String) onRenameLabel;
  final Function(String) onDeleteLabel;

  const LabelListWidget({
    super.key,
    required this.labels,
    required this.currentLabel,
    required this.searchController,
    required this.onSelectLabel,
    required this.onRenameLabel,
    required this.onDeleteLabel,
  });

  @override
  Widget build(BuildContext context) {
    final searchQuery = searchController.text.toLowerCase().trim();
    
    final filteredLabels = searchQuery.isEmpty
        ? labels
        : labels.where((l) => l.toLowerCase().contains(searchQuery)).toList();

    if (labels.isEmpty) {
      return Center(
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
      );
    }

    if (filteredLabels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No labels match "$searchQuery"',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      itemCount: filteredLabels.length,
      itemBuilder: (context, index) {
        final label = filteredLabels[index];
        final isSelected = label == currentLabel;
        
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
    );
  }
}