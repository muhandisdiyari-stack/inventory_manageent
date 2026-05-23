import 'package:flutter/material.dart';

class FieldSelectorCard extends StatelessWidget {
  final List<String> availableFields;
  final Set<String> selectedFields;
  final VoidCallback onSelectionChanged;
  final Function(String) onToggleField;
  final VoidCallback onResetFields;
  final VoidCallback onSelectAllFields;

  const FieldSelectorCard({
    super.key,
    required this.availableFields,
    required this.selectedFields,
    required this.onSelectionChanged,
    required this.onToggleField,
    required this.onResetFields,
    required this.onSelectAllFields,
  });

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
                Icon(Icons.playlist_add_check,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Select Fields',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                    onPressed: onResetFields,
                    child: const Text('Reset')),
                TextButton(
                    onPressed: onSelectAllFields,
                    child: const Text('All')),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: availableFields.map((field) {
                final isSelected = selectedFields.contains(field);
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
                      Text(field,
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: isRequired
                      ? null
                      : (selected) {
                          onToggleField(field);
                          onSelectionChanged();
                        },
                  selectedColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  checkmarkColor:
                      Theme.of(context).colorScheme.primary,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}