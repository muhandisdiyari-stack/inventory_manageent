import 'package:flutter/material.dart';

class FieldSelectorCard extends StatefulWidget {
  final List<String> availableFields;
  final Set<String> selectedFields;
  final VoidCallback onSelectionChanged;

  const FieldSelectorCard({
    super.key,
    required this.availableFields,
    required this.selectedFields,
    required this.onSelectionChanged,
  });

  @override
  State<FieldSelectorCard> createState() => _FieldSelectorCardState();
}

class _FieldSelectorCardState extends State<FieldSelectorCard> {
  void _resetFields() {
    widget.selectedFields.clear();
    widget.selectedFields.addAll(['Name', 'Label', 'Quantity', 'Inventory']);
    widget.onSelectionChanged();
  }

  void _selectAll() {
    widget.selectedFields.addAll(widget.availableFields);
    widget.onSelectionChanged();
  }

  void _toggleField(String field, bool selected) {
    if (field == 'Inventory') return; // Required field
    if (selected) {
      widget.selectedFields.add(field);
    } else {
      widget.selectedFields.remove(field);
    }
    widget.onSelectionChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.playlist_add_check, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Select Fields', style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(onPressed: _resetFields, child: const Text('Reset')),
                TextButton(onPressed: _selectAll, child: const Text('All')),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.availableFields.map((field) {
                final isSelected = widget.selectedFields.contains(field);
                final isRequired = field == 'Inventory';
                return FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isRequired)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.lock,
                            size: 12,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                        ),
                      Text(field, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: isRequired ? null : (selected) => _toggleField(field, selected),
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                  checkmarkColor: Theme.of(context).colorScheme.primary,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}