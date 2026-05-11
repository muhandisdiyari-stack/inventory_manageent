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

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Fields whose names map directly to InventoryItem properties.
/// Kept as a single source of truth so _setItemField and header-matching
/// never diverge due to typos.
abstract class _FieldNames {
  static const name = 'Name';
  static const code = 'Code';
  static const barcode = 'Barcode';
  static const color = 'Color';
  static const material = 'Material';
  static const size = 'Size';
  static const quantity = 'Quantity';
  static const productionDate = 'Production Date';
  static const expireDate = 'Expire Date';
  static const note = 'Note';
}

// ---------------------------------------------------------------------------
// Data class
// ---------------------------------------------------------------------------

class LabelImportStats {
  final int itemsImported;
  final int duplicatesSkipped;
  final int rowsSkipped;
  final int totalRows;

  const LabelImportStats({
    required this.itemsImported,
    required this.duplicatesSkipped,
    required this.rowsSkipped,
    required this.totalRows,
  });
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

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
  Map<String, int> _fieldMapping = {};

  double _progress = 0;
  String _progressText = '';
  final List<String> _progressLog = [];

  // Cap the log so it doesn't grow unbounded on large imports.
  static const _maxLogEntries = 200;

  bool _showResults = false;
  int _totalLabels = 0;
  int _totalImported = 0;
  int _totalDuplicates = 0;
  int _totalErrors = 0;
  Map<String, LabelImportStats>? _resultsByLabel;

  // Cancellation flag – checked at each loop iteration.
  bool _cancelled = false;

  final InventoryService _inventoryService = InventoryService();

  // ---------------------------------------------------------------------------
  // Provider helpers – called lazily so context is always valid
  // ---------------------------------------------------------------------------

  List<String> _getEnabledFields() {
    // Safe to call during build because we use context.read for a one-shot read;
    // the provider is watched at the build level via _buildWelcomeView etc.
    final provider = context.read<InventoryProvider>();
    final settings = provider.currentSettings;
    final fields = <String>[];

    if (settings != null) {
      for (var config in settings.activeFields) {
        fields.add(config.fieldName);
      }
      fields.addAll(settings.customFieldNames);
    } else {
      fields.addAll([
        _FieldNames.name,
        _FieldNames.code,
        _FieldNames.barcode,
        _FieldNames.size,
        _FieldNames.quantity,
        _FieldNames.note,
      ]);
    }

    if (!fields.contains(_FieldNames.name)) fields.insert(0, _FieldNames.name);
    if (!fields.contains(_FieldNames.quantity)) fields.add(_FieldNames.quantity);
    return fields;
  }

  bool _isFieldRequired(String fieldName) {
    final provider = context.read<InventoryProvider>();
    final settings = provider.currentSettings;
    if (settings == null) {
      return fieldName == _FieldNames.name || fieldName == _FieldNames.quantity;
    }
    return settings.isFieldRequired(fieldName);
  }

  // ---------------------------------------------------------------------------
  // Template download
  // ---------------------------------------------------------------------------

  void _downloadTemplate() {
    final enabledFields = _getEnabledFields();

    String getSample(String field, int rowIndex) {
      const names = [
        'Wireless Mouse', 'USB Cable', 'Office Chair',
        'Standing Desk', 'Cotton T-Shirt', 'Denim Jeans',
      ];
      const colors = ['Black', 'White', 'Gray', 'White', 'Blue', 'Blue'];
      const materials = ['Plastic', 'PVC', 'Mesh', 'Wood', 'Cotton', 'Denim'];
      const sizes = ['Standard', '1m', 'Large', '120x60cm', 'M', '32'];

      switch (field) {
        case _FieldNames.name:       return names[rowIndex];
        case _FieldNames.code:       return 'CODE-${rowIndex + 1}00';
        case _FieldNames.barcode:    return '890123456789$rowIndex';
        case _FieldNames.color:      return colors[rowIndex];
        case _FieldNames.material:   return materials[rowIndex];
        case _FieldNames.size:       return sizes[rowIndex];
        case _FieldNames.quantity:   return '${(rowIndex + 1) * 10}';
        case _FieldNames.productionDate: return '2024-0${rowIndex + 1}-15';
        case _FieldNames.expireDate:     return '2026-0${rowIndex + 1}-15';
        case _FieldNames.note:       return 'Sample note ${rowIndex + 1}';
        default:                     return 'Value ${rowIndex + 1}';
      }
    }

    // Use ListToCsvConverter so values with commas/quotes are properly escaped.
    final allRows = <List<dynamic>>[enabledFields];
    for (int i = 0; i < 6; i++) {
      allRows.add(enabledFields.map((f) => getSample(f, i)).toList());
    }
    final csv = const ListToCsvConverter().convert(allRows);
    final bytes = utf8.encode(csv);
    const fileName = 'import_template.csv';

    if (kIsWeb) {
      downloadFileWeb(bytes, fileName, 'text/csv');
    } else {
      _saveLocally(bytes, fileName);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Template ready! Columns: ${enabledFields.join(", ")}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _saveLocally(List<int> bytes, String fileName) async {
    try {
      Directory directory;
      if (Platform.isWindows) {
        directory = Directory('${Platform.environment['USERPROFILE']}\\Downloads');
      } else if (Platform.isLinux || Platform.isMacOS) {
        directory = Directory('${Platform.environment['HOME']}/Downloads');
      } else {
        directory = Directory.systemTemp;
      }
      if (!await directory.exists()) directory = Directory.systemTemp;
      final path = '${directory.path}/$fileName';
      await File(path).writeAsBytes(bytes);
    } catch (e) {
      // Surface the error instead of silently swallowing it.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save file: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // File picking & parsing
  // ---------------------------------------------------------------------------

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
        _showResults = false;
        _resultsByLabel = null;
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

      // Strip UTF-8 BOM (added by Excel on Windows) then normalise line endings.
      contents = contents
          .replaceAll('\uFEFF', '')
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .trim();

      // Use the csv package for parsing so quoted fields are handled correctly.
      final allRows = const CsvToListConverter(eol: '\n').convert(contents);

      final stringRows = <List<String>>[];
      for (var row in allRows) {
        final strRow = row.map((c) => c.toString().trim()).toList();
        if (strRow.isEmpty) continue;
        if (strRow.every((c) => c.isEmpty)) continue;
        if (strRow[0].startsWith('#')) continue;
        stringRows.add(strRow);
      }

      if (stringRows.isEmpty) {
        throw Exception('No valid data found in CSV file.');
      }
      if (stringRows.length < 2) {
        throw Exception(
          'CSV only has a header row. Please add data rows.\n'
          'Header: ${stringRows[0].join(", ")}',
        );
      }

      final headers = stringRows[0];
      final dataRows = stringRows.sublist(1);
      final enabledFields = _getEnabledFields();
      final mapping = <String, int>{};

      // Normalise both sides the same way for comparison.
      String normalise(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

      for (int i = 0; i < headers.length; i++) {
        final h = normalise(headers[i]);
        for (var field in enabledFields) {
          if (h == normalise(field)) {
            mapping[field] = i;
            break;
          }
        }
      }

      if (!mapping.containsKey(_FieldNames.name) && headers.isNotEmpty) {
        mapping[_FieldNames.name] = 0;
      }

      setState(() {
        _rows = dataRows;
        _fieldMapping = mapping;
        _isLoading = false;
      });

      if (mounted) {
        final unmapped = enabledFields.where((f) => !mapping.containsKey(f)).toList();
        final msg = unmapped.isEmpty
            ? 'Ready! ${dataRows.length} items found.'
            : '${dataRows.length} items. Unmapped: ${unmapped.join(", ")}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: unmapped.isEmpty ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  Future<void> _startImport() async {
    if (_rows == null || !_fieldMapping.containsKey(_FieldNames.name)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Name column is required for import'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    _cancelled = false;

    setState(() {
      _isLoading = true;
      _progress = 0;
      _progressText = 'Preparing...';
      _progressLog.clear(); // inside setState so rebuild reflects cleared log
      _showResults = false;
    });

    try {
      await _inventoryService.initializeForInventory(widget.inventoryId);
      final enabledFields = _getEnabledFields();
      final itemFields =
          enabledFields.where((f) => f != _FieldNames.name).toList();
      final nameCol = _fieldMapping[_FieldNames.name]!;

      // Group rows by item name.
      _updateProgress(0.1, 'Grouping items...');
      final byName = <String, List<List<dynamic>>>{};
      for (var row in _rows!) {
        if (row.length > nameCol) {
          final name = row[nameCol].toString().trim();
          if (name.isNotEmpty) {
            byName.putIfAbsent(name, () => []).add(row);
          }
        }
      }
      _addLog('${byName.length} unique items from ${_rows!.length} rows');

      // Create labels for each unique name.
      _updateProgress(0.2, 'Creating labels...');
      final existingLabels = _inventoryService.labels.toSet();
      int labelsCreated = 0;

      for (var name in byName.keys) {
        if (_cancelled) break;
        if (!existingLabels.contains(name)) {
          await _inventoryService.createLabel(name);
          existingLabels.add(name);
          labelsCreated++;
          // Use a UUID/unique ID strategy to avoid microsecond collisions.
          await ActivityLogService().addLog(ActivityLogEntry(
            id: '${DateTime.now().microsecondsSinceEpoch}_$labelsCreated',
            timestamp: DateTime.now(),
            action: 'created',
            entityType: 'label',
            entityName: name,
            inventoryId: widget.inventoryId,
            inventoryName: widget.inventoryName,
            details: 'Label auto-created from CSV import',
          ));
        }
      }
      _addLog(
          'Labels: $labelsCreated new, ${byName.length - labelsCreated} existing');

      // Import items for each label.
      final results = <String, LabelImportStats>{};
      int processed = 0;
      int totalImported = 0;
      int totalDuplicates = 0;
      int totalErrors = 0;
      final total = byName.length;

      for (var entry in byName.entries) {
        if (_cancelled) break;

        processed++;
        final name = entry.key;
        final rows = entry.value;

        // Update progress: 20% reserved for setup, 75% for item import.
        _updateProgress(
          0.2 + 0.75 * (processed / total),
          '$name ($processed/$total)',
        );

        final items = <InventoryItem>[];
        int errors = 0;
        int itemNumber = 0;

        for (var row in rows) {
          try {
            itemNumber++;
            final item = InventoryItem(
              label: name,
              name: itemNumber == 1 ? name : '$name #$itemNumber',
              createdAt: DateTime.now(),
            );
            for (var field in itemFields) {
              final colIndex = _fieldMapping[field];
              if (colIndex != null && row.length > colIndex) {
                final value = row[colIndex].toString().trim();
                if (value.isNotEmpty) _setItemField(item, field, value);
              }
            }
            items.add(item);
          } catch (_) {
            errors++;
          }
        }

        final imported = await _inventoryService.importItems(name, items);
        // Fix: duplicates = original rows minus imported minus parse errors.
        final duplicates = rows.length - imported - errors;

        results[name] = LabelImportStats(
          itemsImported: imported,
          duplicatesSkipped: duplicates < 0 ? 0 : duplicates,
          rowsSkipped: errors,
          totalRows: rows.length,
        );

        totalImported += imported;
        totalDuplicates += (duplicates < 0 ? 0 : duplicates);
        totalErrors += errors;

        // Yield to the event loop without an arbitrary fixed delay.
        await Future.microtask(() {});
      }

      if (_cancelled) {
        _updateProgress(_progress, 'Cancelled.');
        setState(() => _isLoading = false);
        return;
      }

      // Single activity log entry for the whole import.
      await ActivityLogService().addLog(ActivityLogEntry(
        id: '${DateTime.now().microsecondsSinceEpoch}_bulk',
        timestamp: DateTime.now(),
        action: 'created',
        entityType: 'item',
        entityName: 'CSV Import',
        inventoryId: widget.inventoryId,
        inventoryName: widget.inventoryName,
        details: 'Bulk import: $total labels, $totalImported items',
      ));

      _updateProgress(1, 'Complete!');
      _addLog('Done! $totalImported items imported across $total labels.');

      if (!mounted) return;
      setState(() {
        _totalLabels = total;
        _totalImported = totalImported;
        _totalDuplicates = totalDuplicates;
        _totalErrors = totalErrors;
        _resultsByLabel = results;
        _showResults = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _cancelled = true; // stop the loop if the widget is disposed mid-import
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Progress helpers
  // ---------------------------------------------------------------------------

  void _updateProgress(double progress, String text) {
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _progressText = text;
    });
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _progressLog.add(message);
      // Cap log length to avoid unbounded memory growth.
      if (_progressLog.length > _maxLogEntries) {
        _progressLog.removeAt(0);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Field setter – uses constants to avoid magic-string mismatches
  // ---------------------------------------------------------------------------

  void _setItemField(InventoryItem item, String field, String value) {
    switch (field) {
      case _FieldNames.name:
        break; // handled separately
      case _FieldNames.code:
        item.code = value;
        break;
      case _FieldNames.barcode:
        item.barcode = value;
        break;
      case _FieldNames.color:
        item.color = value;
        break;
      case _FieldNames.material:
        item.material = value;
        break;
      case _FieldNames.size:
        item.size = value;
        break;
      case _FieldNames.productionDate:
        item.productionDate = DateTime.tryParse(value);
        break;
      case _FieldNames.expireDate:
        item.expireDate = DateTime.tryParse(value);
        break;
      case _FieldNames.note:
        item.note = value;
        break;
      case _FieldNames.quantity:
        item.quantity = int.tryParse(value) ?? 0;
        break;
      default:
        if (value.isNotEmpty) item.customFields[field] = value;
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Watch the provider here so the field list stays fresh.
    context.watch<InventoryProvider>();
    final fields = _getEnabledFields();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk Import'),
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
                  ? _buildWelcomeView(fields)
                  : _buildPreviewView(fields),
    );
  }

  // ---------------------------------------------------------------------------
  // Welcome view
  // ---------------------------------------------------------------------------

  Widget _buildWelcomeView(List<String> fields) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withOpacity(0.3),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(Icons.cloud_upload,
                size: 48, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 24),
          Text(
            'Bulk Import',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Import items from a CSV file.\n'
            'Each item Name becomes its own label automatically.\n'
            'Download the template, fill in your data, and re-import.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.grey[600], fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CSV Columns (${fields.length}):',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: fields
                      .map((f) => Chip(
                            label: Text(f,
                                style: const TextStyle(fontSize: 11)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: _isFieldRequired(f)
                                ? Colors.red.shade50
                                : null,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloadTemplate,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Template'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.file_open, size: 18),
                  label: const Text('Choose CSV'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Preview view
  // ---------------------------------------------------------------------------

  Widget _buildPreviewView(List<String> fields) {
    final unmapped =
        fields.where((f) => !_fieldMapping.containsKey(f)).toList();
    final unmappedRequired =
        unmapped.where((f) => _isFieldRequired(f)).toList();

    final names = <String, int>{};
    final nameCol = _fieldMapping[_FieldNames.name];
    if (nameCol != null) {
      for (var row in _rows!) {
        if (row.length > nameCol) {
          final name = row[nameCol].toString().trim();
          if (name.isNotEmpty) names[name] = (names[name] ?? 0) + 1;
        }
      }
    }

    final showingCount = names.length > 50 ? 50 : names.length;

    return Column(
      children: [
        // Summary card
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fileName ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(
                      '${names.length} unique names from ${_rows!.length} rows',
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    if (unmapped.isNotEmpty)
                      Text(
                        'Unmapped: ${unmapped.join(", ")}',
                        style: TextStyle(
                            color: Colors.orange[700], fontSize: 11),
                      ),
                  ],
                ),
              ),
              FilledButton(
                onPressed:
                    unmappedRequired.isEmpty ? _startImport : null,
                child: const Text('Import All'),
              ),
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
            ),
            child: Text(
              'Required fields not mapped: ${unmappedRequired.join(", ")}',
              style: TextStyle(fontSize: 12, color: Colors.red[700]),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(
                'Labels to be created (from Name column):',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                    fontSize: 13),
              ),
              const Spacer(),
              if (names.length > 50)
                Text(
                  'Showing $showingCount of ${names.length}',
                  style:
                      TextStyle(fontSize: 11, color: Colors.orange[700]),
                ),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: showingCount,
            itemBuilder: (_, i) {
              final name = names.keys.elementAt(i);
              final count = names[name]!;
              return Card(
                margin: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.green.shade100,
                    child: Text('$count',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade700)),
                  ),
                  title:
                      Text(name, style: const TextStyle(fontSize: 13)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Progress view
  // ---------------------------------------------------------------------------

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
                    value: _progress, strokeWidth: 8),
              ),
              Text(
                '${(_progress * 100).toInt()}%',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(_progressText,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _cancelled = true),
            icon: const Icon(Icons.stop_circle_outlined, size: 16),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.builder(
                itemCount: _progressLog.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    _progressLog[i],
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.grey[700]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Results view
  // ---------------------------------------------------------------------------

  Widget _buildResultsView() {
    // _resultsByLabel is always non-null when _showResults is true.
    final results = _resultsByLabel!;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade600,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Import Complete!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStat('Labels', _totalLabels),
                  _buildStat('Imported', _totalImported),
                  _buildStat('Duplicates', _totalDuplicates),
                  _buildStat('Errors', _totalErrors),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: results.length,
            itemBuilder: (_, i) {
              final name = results.keys.elementAt(i);
              final stats = results[name]!;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: stats.rowsSkipped > 0
                        ? Colors.orange.shade100
                        : Colors.green.shade100,
                    child: Icon(
                      stats.rowsSkipped > 0
                          ? Icons.warning
                          : Icons.check,
                      size: 16,
                      color: stats.rowsSkipped > 0
                          ? Colors.orange.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                  title: Text(name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '${stats.itemsImported} imported'
                    '${stats.duplicatesSkipped > 0 ? ', ${stats.duplicatesSkipped} duplicates' : ''}'
                    '${stats.rowsSkipped > 0 ? ', ${stats.rowsSkipped} errors' : ''}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[600]),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check),
              label: const Text('Back to Inventory'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, int value) {
    return Column(
      children: [
        Text(
          '$value',
          // Use theme-aware white by relying on the green background context.
          style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}