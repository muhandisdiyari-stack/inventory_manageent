import 'package:flutter/material.dart';

class PreviewCard extends StatelessWidget {
  final List<List<dynamic>> previewData;
  final int totalItems;
  final VoidCallback onClear;

  const PreviewCard({
    super.key,
    required this.previewData,
    required this.totalItems,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (previewData.isEmpty) return const SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.preview, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Preview ($totalItems items)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(onPressed: onClear, child: const Text('Clear')),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 400),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 20,
                    headingRowHeight: 40,
                    dataRowMinHeight: 32,
                    dataRowMaxHeight: 40,
                    columns: previewData.first.map((col) {
                      return DataColumn(
                        label: Text(
                          col.toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      );
                    }).toList(),
                    rows: previewData.skip(1).map((row) {
                      return DataRow(
                        cells: row.map((cell) {
                          return DataCell(
                            Text(cell.toString(), style: const TextStyle(fontSize: 11)),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}