import 'dart:convert';
import 'dart:io' show File, Directory, Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/file_export.dart';
import '../../inventory_management/services/inventory_service.dart';
import '../../inventory_management/models/inventory_item.dart';
import '../../inventory_management/providers/inventory_provider.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';

class BulkImportScreen extends StatefulWidget {
  final String inventoryId;
  final String inventoryName;

  const BulkImportScreen({
    super.key,
    required this.inventoryId,
    required this.inventoryName,
  });

  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  List<List<dynamic>>? _rows;
  String? _fileName;
  bool _isLoading = false;

  int _labelColumnIndex = 0;
  Map<String, int> _fieldMapping = {};

  double _progress = 0;
  String _progressText = '';
  final List<String> _progressLog = [];

  Map<String, LabelImportStats>? _results;
  bool _showResults = false;

  final InventoryService _inventoryService = InventoryService();

  List<String> _getEnabledFields() {
    final provider = context.read<InventoryProvider>();
    final settings = provider.currentSettings;

    if (settings == null) {
      return ['Name', 'Code', 'Barcode', 'Size', 'Quantity', 'Note'];
    }

    final fields = <String>[];
    for (var config in settings.activeFields) {
      if (config.fieldName != 'Label') {
        fields.add(config.fieldName);
      }
    }
    fields.addAll(settings.customFieldNames);
    return fields;
  }

  bool _isFieldRequired(String fieldName) {
    final provider = context.read<InventoryProvider>();
    final settings = provider.currentSettings;
    if (settings == null) return fieldName == 'Name' || fieldName == 'Quantity';
    return settings.isFieldRequired(fieldName);
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _isLoading = true;
        _fileName = result.files.single.name;
        _results = null;
        _showResults = false;
      });

      String contents;
      if (kIsWeb) {
        final bytes = result.files.single.bytes;
        if (bytes == null) throw Exception('Cannot read file on web');
        contents = utf8.decode(bytes);
      } else {
        final path = result.files.single.path;
        if (path == null) throw Exception('Cannot read file path');
        contents = await File(path).readAsString();
      }

      final csvRows = const CsvToListConverter().convert(contents);

      if (csvRows.isEmpty) throw Exception('The CSV file is empty');

      final headers = csvRows[0].map((h) => h.toString().trim()).toList();
      final dataRows = csvRows
          .sublist(1)
          .where((row) =>
              row.isNotEmpty &&
              row.any((cell) => cell.toString().trim().isNotEmpty))
          .toList();

      if (dataRows.isEmpty) throw Exception('No data rows found');

      int labelCol = 0;
      for (int i = 0; i < headers.length; i++) {
        if (headers[i].toLowerCase() == 'label' ||
            headers[i].toLowerCase() == 'category' ||
            headers[i].toLowerCase() == 'group') {
          labelCol = i;
          break;
        }
      }

      final enabledFields = _getEnabledFields();
      final mapping = <String, int>{};
      for (int i = 0; i < headers.length; i++) {
        if (i == labelCol) continue;
        for (var field in enabledFields) {
          if (headers[i].toLowerCase() == field.toLowerCase()) {
            mapping[field] = i;
            break;
          }
        }
      }

      if (!mapping.containsKey('Name') && enabledFields.contains('Name')) {
        for (int i = 0; i < headers.length; i++) {
          if (i != labelCol) {
            mapping['Name'] = i;
            break;
          }
        }
      }

      final labels = <String, int>{};
      for (var row in dataRows) {
        if (row.length > labelCol) {
          final label = row[labelCol].toString().trim();
          if (label.isNotEmpty) {
            labels[label] = (labels[label] ?? 0) + 1;
          }
        }
      }

      setState(() {
        _rows = dataRows;
        _labelColumnIndex = labelCol;
        _fieldMapping = mapping;
        _isLoading = false;
      });

      if (mounted) {
        final unmappedFields =
            enabledFields.where((f) => !mapping.containsKey(f)).toList();
        final message = unmappedFields.isEmpty
            ? 'Found ${labels.length} labels, ${dataRows.length} items. All fields mapped!'
            : 'Found ${labels.length} labels. Unmapped fields: ${unmappedFields.join(", ")}';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: unmappedFields.isEmpty ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _startBulkImport() async {
    if (_rows == null) return;

    if (!_fieldMapping.containsKey('Name')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name field must be mapped before importing'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _progress = 0;
      _progressText = 'Preparing import...';
      _progressLog.clear();
      _showResults = false;
    });

    try {
      await _inventoryService.initializeForInventory(widget.inventoryId);
      final enabledFields = _getEnabledFields();

      _updateProgress(0.05, 'Grouping items by label...');
      final itemsByLabel = <String, List<List<dynamic>>>{};
      int rowsWithoutLabel = 0;
      int rowsWithoutName = 0;

      for (var row in _rows!) {
        if (row.length > _labelColumnIndex) {
          final label = row[_labelColumnIndex].toString().trim();
          if (label.isNotEmpty) {
            final nameCol = _fieldMapping['Name'];
            if (nameCol != null && row.length > nameCol) {
              final name = row[nameCol].toString().trim();
              if (name.isNotEmpty) {
                itemsByLabel.putIfAbsent(label, () => []).add(row);
              } else {
                rowsWithoutName++;
              }
            } else {
              rowsWithoutName++;
            }
          } else {
            rowsWithoutLabel++;
          }
        } else {
          rowsWithoutLabel++;
        }
      }

      _addLog('${itemsByLabel.length} labels, ${_rows!.length} total rows');
      if (rowsWithoutLabel > 0) {
        _addLog('$rowsWithoutLabel rows skipped (no label)');
      }
      if (rowsWithoutName > 0) {
        _addLog('$rowsWithoutName rows skipped (no name)');
      }
      _addLog('Enabled fields: ${enabledFields.join(", ")}');
      _addLog('Mapped fields: ${_fieldMapping.keys.join(", ")}');

      _updateProgress(0.1, 'Creating labels...');
      final existingLabels = _inventoryService.labels.toSet();
      int labelsCreated = 0;

      for (var label in itemsByLabel.keys) {
        if (!existingLabels.contains(label)) {
          await _inventoryService.createLabel(label);
          existingLabels.add(label);
          labelsCreated++;
          _addLog('  Created label: "$label"');

          await ActivityLogService().addLog(ActivityLogEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            timestamp: DateTime.now(),
            action: 'created',
            entityType: 'label',
            entityName: label,
            inventoryId: widget.inventoryId,
            inventoryName: widget.inventoryName,
            details: 'Label created during bulk import',
          ));
        }
      }
      _addLog('Labels: $labelsCreated created, ${itemsByLabel.length - labelsCreated} existing');

      final results = <String, LabelImportStats>{};
      int processedLabels = 0;
      final totalLabels = itemsByLabel.length;
      int totalImported = 0;

      for (var entry in itemsByLabel.entries) {
        final label = entry.key;
        final rows = entry.value;

        final progress = 0.1 + (0.85 * (processedLabels / totalLabels));
        _updateProgress(progress, 'Importing "$label" (${processedLabels + 1}/$totalLabels)...');

        final items = <InventoryItem>[];
        int rowsWithErrors = 0;

        for (var row in rows) {
          try {
            final item = InventoryItem(label: label);

            for (var field in enabledFields) {
              final colIndex = _fieldMapping[field];
              if (colIndex != null && row.length > colIndex) {
                final value = row[colIndex].toString().trim();
                if (value.isNotEmpty) {
                  _setItemField(item, field, value);
                }
              }
            }

            if (item.name.isNotEmpty) {
              items.add(item);
            } else {
              rowsWithErrors++;
            }
          } catch (_) {
            rowsWithErrors++;
          }
        }

        final importedCount = await _inventoryService.importItems(label, items);
        final duplicates = items.length - importedCount;

        results[label] = LabelImportStats(
          itemsImported: importedCount,
          duplicatesSkipped: duplicates,
          rowsSkipped: rowsWithErrors,
          totalRows: rows.length,
        );

        totalImported += importedCount;
        _addLog('  "$label": $importedCount items ($duplicates duplicates, $rowsWithErrors errors)');
        processedLabels++;

        await Future.delayed(const Duration(milliseconds: 50));
      }

      _updateProgress(0.95, 'Finalizing...');
      await ActivityLogService().addLog(ActivityLogEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        action: 'created',
        entityType: 'item',
        entityName: 'Bulk Import',
        inventoryId: widget.inventoryId,
        inventoryName: widget.inventoryName,
        details: 'Bulk import: ${itemsByLabel.length} labels, $totalImported items imported',
      ));

      _updateProgress(1.0, 'Complete!');
      _addLog('Import completed! $totalImported items across ${itemsByLabel.length} labels');

      setState(() {
        _results = results;
        _showResults = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _addLog('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _updateProgress(double progress, String text) {
    setState(() {
      _progress = progress;
      _progressText = text;
    });
  }

  void _addLog(String message) {
    setState(() {
      _progressLog.add(message);
    });
  }

  void _setItemField(InventoryItem item, String field, String value) {
    switch (field.toLowerCase()) {
      case 'name': item.name = value;
      case 'code': item.code = value;
      case 'barcode': item.barcode = value;
      case 'color': item.color = value;
      case 'material': item.material = value;
      case 'size': item.size = value;
      case 'production date': item.productionDate = DateTime.tryParse(value);
      case 'expire date': item.expireDate = DateTime.tryParse(value);
      case 'note': item.note = value;
      case 'quantity': item.quantity = int.tryParse(value) ?? 0;
      default:
        if (value.isNotEmpty) item.customFields[field] = value;
    }
  }

  void _downloadTemplate() {
    final enabledFields = _getEnabledFields();

    final buffer = StringBuffer();
    buffer.write('Label,${enabledFields.join(",")}\n');

    final sampleLabels = ['Electronics', 'Furniture', 'Clothing'];
    for (var label in sampleLabels) {
      final row = <String>[label];
      for (var field in enabledFields) {
        row.add(_getSampleValue(field));
      }
      buffer.write('${row.join(",")}\n');
    }

    final row = <String>[sampleLabels.first];
    for (var field in enabledFields) {
      row.add(_getSampleValue(field, variant: true));
    }
    buffer.write('${row.join(",")}\n');

    final bytes = utf8.encode(buffer.toString());
    if (kIsWeb) {
      downloadFileWeb(bytes, 'bulk_import_template.csv', 'text/csv');
    } else {
      _saveTemplateLocally(bytes);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Template downloaded with your configured fields!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _getSampleValue(String field, {bool variant = false}) {
    switch (field.toLowerCase()) {
      case 'name': return variant ? 'USB Cable' : 'Wireless Mouse';
      case 'code': return variant ? 'CABLE-001' : 'MOUSE-001';
      case 'barcode': return variant ? '8901234567891' : '8901234567890';
      case 'color': return variant ? 'Black' : 'White';
      case 'material': return variant ? 'PVC' : 'Plastic';
      case 'size': return variant ? '1m' : 'Standard';
      case 'quantity': return variant ? '100' : '50';
      case 'production date': return '2024-01-15';
      case 'expire date': return '2026-01-15';
      case 'note': return variant ? 'Fast charging' : 'Ergonomic design';
      default: return variant ? 'Value B' : 'Value A';
    }
  }

  Future<void> _saveTemplateLocally(List<int> bytes) async {
    try {
      Directory directory;
      if (Platform.isWindows) {
        directory = Directory('${Platform.environment['USERPROFILE']}\\Documents');
      } else if (Platform.isLinux || Platform.isMacOS) {
        directory = Directory('${Platform.environment['HOME']}/Documents');
      } else {
        directory = Directory.systemTemp;
      }
      final path = '${directory.path}/bulk_import_template.csv';
      await File(path).writeAsBytes(bytes);
    } catch (_) {
      // Silently fail - template saving is optional
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk Import (Labels + Items)'),
        actions: [
          if (_showResults)
            TextButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check),
              label: const Text('Done'),
            ),
        ],
      ),
      body: _isLoading
          ? _buildProgressView()
          : _showResults
              ? _buildResultsView()
              : _rows == null
                  ? _buildWelcomeView()
                  : _buildPreviewView(),
    );
  }

  Widget _buildWelcomeView() {
    final enabledFields = _getEnabledFields();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(Icons.cloud_upload, size: 48, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text('Bulk Import',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              'Import all labels and items from one CSV file.\nOnly fields enabled in Settings will be imported.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enabled fields (${enabledFields.length}):',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: enabledFields.map((field) {
                      final required = _isFieldRequired(field);
                      return Chip(
                        label: Text(required ? '$field *' : field, style: const TextStyle(fontSize: 11)),
                        backgroundColor: required ? Colors.red.shade50 : Colors.green.shade50,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _downloadTemplate,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Template'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.file_open),
                  label: const Text('Choose CSV File'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewView() {
    final enabledFields = _getEnabledFields();
    final unmappedFields = enabledFields.where((f) => !_fieldMapping.containsKey(f)).toList();
    final unmappedRequired = unmappedFields.where((f) => _isFieldRequired(f)).toList();

    final labels = <String, int>{};
    for (var row in _rows!) {
      if (row.length > _labelColumnIndex) {
        final label = row[_labelColumnIndex].toString().trim();
        if (label.isNotEmpty) {
          labels[label] = (labels[label] ?? 0) + 1;
        }
      }
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_fileName ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('${labels.length} labels \u2022 ${_rows!.length} items',
                            style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: unmappedRequired.isEmpty ? _startBulkImport : null,
                    child: const Text('Import All'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Mapped fields: ${_fieldMapping.keys.join(", ")}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              if (unmappedFields.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Unmapped: ${unmappedFields.join(", ")}',
                    style: TextStyle(fontSize: 11, color: Colors.orange[700], fontWeight: FontWeight.w500)),
              ],
            ],
          ),
        ),
        if (unmappedRequired.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 18, color: Colors.red[700]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Required fields not mapped: ${unmappedRequired.join(", ")}',
                    style: TextStyle(fontSize: 12, color: Colors.red[700]),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              const Icon(Icons.label, size: 16),
              const SizedBox(width: 8),
              Text('Labels found:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: labels.length,
            itemBuilder: (context, index) {
              final label = labels.keys.elementAt(index);
              final count = labels[label]!;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text('$count',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                  ),
                  title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text('$count items', style: const TextStyle(fontSize: 11)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProgressView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: 8,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              Text('${(_progress * 100).toInt()}%',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 24),
          Text(_progressText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.builder(
                itemCount: _progressLog.length,
                itemBuilder: (context, index) {
                  return Text(
                    _progressLog[index],
                    style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey[700]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    if (_results == null) return const SizedBox();

    int totalImported = 0, totalDuplicates = 0, totalSkipped = 0;
    for (var stat in _results!.values) {
      totalImported += stat.itemsImported;
      totalDuplicates += stat.duplicatesSkipped;
      totalSkipped += stat.rowsSkipped;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.green.shade400, Colors.green.shade600]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 48),
              const SizedBox(height: 12),
              const Text('Bulk Import Complete!',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildResultStat('Labels', _results!.length.toString()),
                  _buildResultStat('Imported', totalImported.toString()),
                  _buildResultStat('Duplicates', totalDuplicates.toString()),
                  _buildResultStat('Errors', totalSkipped.toString()),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _results!.length,
            itemBuilder: (context, index) {
              final label = _results!.keys.elementAt(index);
              final stats = _results![label]!;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: stats.rowsSkipped > 0 ? Colors.orange.shade100 : Colors.green.shade100,
                    child: Icon(
                      stats.rowsSkipped > 0 ? Icons.warning : Icons.check,
                      color: stats.rowsSkipped > 0 ? Colors.orange.shade700 : Colors.green.shade700,
                      size: 18,
                    ),
                  ),
                  title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${stats.itemsImported} items imported',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildDetailRow('Items imported', stats.itemsImported.toString()),
                          _buildDetailRow('Duplicates skipped', stats.duplicatesSkipped.toString()),
                          if (stats.rowsSkipped > 0)
                            _buildDetailRow('Rows with errors', stats.rowsSkipped.toString()),
                          _buildDetailRow('Total rows', stats.totalRows.toString()),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

class LabelImportStats {
  final int itemsImported;
  final int duplicatesSkipped;
  final int rowsSkipped;
  final int totalRows;

  LabelImportStats({
    required this.itemsImported,
    required this.duplicatesSkipped,
    required this.rowsSkipped,
    required this.totalRows,
  });
}