import 'package:flutter/material.dart';
import '../services/csv_service.dart';

class GeneratedReportCard extends StatelessWidget {
  final String? fileName;
  final int totalItems;
  final String? csvData;
  final VoidCallback onDownloadAgain;
  final VoidCallback onCopyToClipboard;
  final CsvService csvService;

  const GeneratedReportCard({
    super.key,
    this.fileName,
    required this.totalItems,
    this.csvData,
    required this.onDownloadAgain,
    required this.onCopyToClipboard,
    required this.csvService,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Fixed: Use theme-adaptive colors instead of hardcoded green
    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: colorScheme.onSecondaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Report Generated',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'File: ${fileName ?? "report.csv"}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSecondaryContainer.withValues(alpha: 0.7),
              ),
            ),
            Text(
              'Items: $totalItems',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSecondaryContainer.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDownloadAgain,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Download Again', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCopyToClipboard,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}