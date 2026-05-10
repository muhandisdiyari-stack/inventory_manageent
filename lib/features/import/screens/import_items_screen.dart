import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../inventory_management/services/inventory_service.dart';
import '../../inventory_management/models/inventory_item.dart';
import '../../inventory_management/models/inventory_settings.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';

class ImportItemsScreen extends StatefulWidget {
  final String inventoryId;
  final String inventoryName;
  final String label;
  final InventorySettings? settings;

  const ImportItemsScreen({
    super.key,
    required this.inventoryId,
    required this.inventoryName,
    required this.label,
    this.settings,
  });

  @override
  State<ImportItemsScreen> createState() => _ImportItemsScreenState();
}

class _ImportItemsScreenState extends State<ImportItemsScreen> {
  List<String>? _csvHeaders;
  List<List<dynamic>>? _csvData;
  String? _fileName;
  bool _isLoading = false;
  Map<String, int> _columnMapping = {};
  final InventoryService _inventoryService = InventoryService();

  static const List<String> _standardFields = [
    'Name', 'Code', 'Barcode', 'Color', 'Material', 'Size',
    'Production Date', 'Expire Date', 'Note', 'Quantity',
  ];

  @override
  void initState() {
    super.initState();
    _columnMapping['Name'] = 0; // Name defaults to first column
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _isLoading = true);

        final file = File(result.files.single.path!);
        final contents = await file.readAsString();
        final rows = const CsvToListConverter().convert(contents);

        if (rows.isNotEmpty) {
          final headers = rows[0].map((h) => h.toString()).toList();
          setState(() {
            _csvHeaders = headers;
            _csvData = rows.sublist(1);
            _fileName = result.files.single.name;
            // Auto-map columns by name
            _columnMapping = {};
            for (int i = 0; i < headers.length; i++) {
              for (var field in _standardFields) {
                if (headers[i].toLowerCase() == field.toLowerCase()) {
                  _columnMapping[field] = i;
                  break;
                }
              }
              // Check custom fields
              for (var customField in widget.settings?.customFieldNames ?? []) {
                if (headers[i].toLowerCase() == customField.toLowerCase()) {
                  _columnMapping[customField] = i;
                  break;
                }
              }
            }
            // Name defaults to first column if not mapped
            if (!_columnMapping.containsKey('Name')) {
              _columnMapping['Name'] = 0;
            }
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

  List<String> _getAvailableFields() {
    final fields = <String>[..._standardFields];
    if (widget.settings != null) {
      fields.addAll(widget.settings!.customFieldNames);
    }
    return fields;
  }

  void _clearColumn(String field) {
    setState(() => _columnMapping.remove(field));
  }

  Future<void> _importItems() async {
    if (_csvData == null || !_columnMapping.containsKey('Name')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name column is required'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _inventoryService.initializeForInventory(widget.inventoryId);
      
      final items = <InventoryItem>[];

      for (var row in _csvData!) {
        final item = InventoryItem(label: widget.label);

        for (var entry in _columnMapping.entries) {
          if (row.length > entry.value) {
            final value = row[entry.value].toString().trim();
            _setItemField(item, entry.key, value);
          }
        }

        items.add(item);
      }

      final importedCount = await _inventoryService.importItems(widget.label, items);

      // Log activity
      final logEntry = ActivityLogEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        action: 'created',
        entityType: 'item',
        entityName: 'CSV Import',
        inventoryId: widget.inventoryId,
        inventoryName: widget.inventoryName,
        labelName: widget.label,
        details: 'Imported $importedCount items from CSV to label "${widget.label}"',
      );
      await ActivityLogService().addLog(logEntry);

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Imported $importedCount items (${items.length - importedCount} duplicates skipped)'),
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

  void _setItemField(InventoryItem item, String field, String value) {
    switch (field.toLowerCase()) {
      case 'name': item.name = value; break;
      case 'code': item.code = value; break;
      case 'barcode': item.barcode = value; break;
      case 'color': item.color = value; break;
      case 'material': item.material = value; break;
      case 'size': item.size = value; break;
      case 'production date':
        item.productionDate = DateTime.tryParse(value);
        break;
      case 'expire date':
        item.expireDate = DateTime.tryParse(value);
        break;
      case 'note': item.note = value; break;
      case 'quantity':
        item.quantity = int.tryParse(value) ?? 0;
        break;
      default:
        // Custom field
        if (value.isNotEmpty) {
          item.customFields[field] = value;
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Items from CSV'),
        actions: [
          if (_csvData != null)
            TextButton.icon(
              onPressed: _isLoading ? null : _importItems,
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
                      Text('Import items to "${widget.label}"',
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Select a CSV file to import items',
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
                    // Column mapping
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Text('Map CSV columns to item fields:',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text('Name column is required',
                              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                          const SizedBox(height: 12),
                          ..._getAvailableFields().map((field) {
                            final mappedIndex = _columnMapping[field];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  field == 'Name' ? Icons.star : Icons.link,
                                  color: field == 'Name' ? Colors.orange : null,
                                  size: 20,
                                ),
                                title: Text(field, style: const TextStyle(fontSize: 14)),
                                subtitle: mappedIndex != null
                                    ? Text('Column ${mappedIndex + 1}: ${_csvHeaders![mappedIndex]}',
                                        style: const TextStyle(fontSize: 12))
                                    : const Text('Not mapped', style: TextStyle(fontSize: 12)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (field != 'Name' && mappedIndex != null)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () => _clearColumn(field),
                                      ),
                                    const Icon(Icons.chevron_right, size: 18),
                                  ],
                                ),
                                onTap: () => _showColumnPicker(field),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  void _showColumnPicker(String field) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Map "$field" to column:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ..._csvHeaders!.asMap().entries.map((entry) {
                final isMapped = _columnMapping.values.contains(entry.key) &&
                    _columnMapping[field] != entry.key;
                return ListTile(
                  leading: Icon(
                    isMapped ? Icons.block : Icons.radio_button_unchecked,
                    color: isMapped ? Colors.grey : null,
                    size: 20,
                  ),
                  title: Text('Column ${entry.key + 1}: ${entry.value}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isMapped ? Colors.grey : null,
                      )),
                  onTap: isMapped
                      ? null
                      : () {
                          setState(() => _columnMapping[field] = entry.key);
                          Navigator.pop(ctx);
                        },
                );
              }),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() => _columnMapping.remove(field));
                  Navigator.pop(ctx);
                },
                child: const Text('Skip this field'),
              ),
            ],
          ),
        );
      },
    );
  }
}