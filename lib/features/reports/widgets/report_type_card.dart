import 'package:flutter/material.dart';

class ReportTypeCard extends StatelessWidget {
  final String selectedType;
  final ValueChanged<String> onTypeChanged;

  const ReportTypeCard({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
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
                Icon(Icons.filter_list, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Report Filter', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'all',
                  label: Text('All Items'),
                  icon: Icon(Icons.inventory_2, size: 16),
                ),
                ButtonSegment<String>(
                  value: 'expiring',
                  label: Text('Expiring'),
                  icon: Icon(Icons.warning_amber, size: 16),
                ),
                ButtonSegment<String>(
                  value: 'expired',
                  label: Text('Expired'),
                  icon: Icon(Icons.error_outline, size: 16),
                ),
              ],
              selected: {selectedType},
              onSelectionChanged: (Set<String> value) => onTypeChanged(value.first),
            ),
          ],
        ),
      ),
    );
  }
}