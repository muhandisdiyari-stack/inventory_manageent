import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../inventory_management/services/inventory_service.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';

class ImportLabelsScreen extends StatefulWidget {
  final String inventoryId;
  final String inventoryName;

  const ImportLabelsScreen({
    super.key,
    required this.inventoryId,
    required this.inventoryName,
  });

  @override
  State<ImportLabelsScreen> createState() => _ImportLabelsScreenState();
}

class _ImportLabelsScreenState extends State<ImportLabelsScreen> {
  List<String>? _csvHeaders;
  List<List<dynamic>>? _csvData;
  String? _fileName;
  bool _isLoading = false;
  int? _selectedNameColumn;
  final InventoryService _inventoryService = InventoryService();

  @override
  void initState() {
    super.initState();
    _selectedNameColumn = 0; // Default to first column
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _isLoading = true;
          _fileName = result.files.single.name;
        });

        final file = File(result.files.single.path!);
        final contents = await file.readAsString();
        final rows = const CsvToListConverter().convert(contents);

        if (rows.isNotEmpty) {
          setState(() {
            _csvHeaders = rows[0].map((h) => h.toString()).toList();
            _csvData = rows.sublist(1);
            _selectedNameColumn = 0; // Default to first column
          });
        }

        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _importLabels() async {
    if (_csvData == null || _selectedNameColumn == null) return;

    setState(() => _isLoading = true);

    try {
      await _inventoryService.initializeForInventory(widget.inventoryId);
      
      final existingLabels = _inventoryService.labels.toSet();
      int importedCount = 0;
      int skippedCount = 0;

      for (var row in _csvData!) {
        if (row.length > _selectedNameColumn!) {
          final labelName = row[_selectedNameColumn!].toString().trim();
          if (labelName.isNotEmpty && !existingLabels.contains(labelName)) {
            await _inventoryService.createLabel(labelName);
            existingLabels.add(labelName);
            importedCount++;
            
            // Log activity
            final logEntry = ActivityLogEntry(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              timestamp: DateTime.now(),
              action: 'created',
              entityType: 'label',
              entityName: labelName,
              inventoryId: widget.inventoryId,
              inventoryName: widget.inventoryName,
              details: 'Label imported from CSV: "$labelName"',
            );
            await ActivityLogService().addLog(logEntry);
          } else {
            skippedCount++;
          }
        }
      }

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Imported $importedCount labels, skipped $skippedCount duplicates'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Labels from CSV'),
        actions: [
          if (_csvData != null)
            TextButton.icon(
              onPressed: _isLoading ? null : _importLabels,
              icon: const Icon(Icons.check),
              label: const Text('Import'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _csvData == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.upload_file, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text('Select a CSV file to import labels',
                          style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('The first column should contain label names',
                          style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.file_open),
                        label: const Text('Choose CSV File'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // File info
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      child: Row(
                        children: [
                          const Icon(Icons.description),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_fileName ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text('${_csvData!.length} rows found',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Column selection
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Select the column containing label names:',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                            value: _selectedNameColumn,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                            ),
                            items: _csvHeaders!.asMap().entries.map((entry) {
                              return DropdownMenuItem(
                                value: entry.key,
                                child: Text('Column ${entry.key + 1}: ${entry.value}'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() => _selectedNameColumn = value);
                            },
                          ),
                        ],
                      ),
                    ),
                    // Preview
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('Preview (first 20 rows):',
                                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _csvData!.length > 20 ? 20 : _csvData!.length,
                              itemBuilder: (context, index) {
                                final row = _csvData![index];
                                final label = _selectedNameColumn != null && row.length > _selectedNameColumn!
                                    ? row[_selectedNameColumn!].toString()
                                    : '';
                                final isDuplicate = _inventoryService.hasLabel(label);
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isDuplicate ? Icons.warning : Icons.check_circle,
                                    color: isDuplicate ? Colors.orange : Colors.green,
                                    size: 20,
                                  ),
                                  title: Text(label, style: const TextStyle(fontSize: 14)),
                                  subtitle: isDuplicate
                                      ? const Text('Already exists', style: TextStyle(fontSize: 11, color: Colors.orange))
                                      : null,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}