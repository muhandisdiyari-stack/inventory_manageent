import 'package:flutter/material.dart';

class ActionButtons extends StatelessWidget {
  final bool hasSelection;
  final VoidCallback onPreview;
  final VoidCallback onDownload;

  const ActionButtons({
    super.key,
    required this.hasSelection,
    required this.onPreview,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: hasSelection ? onPreview : null,
            icon: const Icon(Icons.preview),
            label: const Text('Preview'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: hasSelection ? onDownload : null,
            icon: const Icon(Icons.download),
            label: const Text('Download CSV'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
              backgroundColor: Colors.green,
            ),
          ),
        ),
      ],
    );
  }
}