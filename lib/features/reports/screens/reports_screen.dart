import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../inventory_management/providers/inventory_provider.dart';
import '../services/csv_service.dart';
import '../widgets/report_type_card.dart';
import '../widgets/field_selector_card.dart';
import '../widgets/action_buttons.dart';
import '../widgets/generated_report_card.dart';
import '../widgets/preview_card.dart';
import '../widgets/progress_view.dart';
import '../features/report_generator.dart';
import '../features/report_previewer.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final Set<String> _selectedFields = {'Name', 'Code', 'Label', 'Quantity', 'Inventory'};
  String _reportType = 'all';
  bool _isGenerating = false;
  double _progress = 0;
  String? _statusMessage;
  List<List<dynamic>>? _previewData;
  String? _lastGeneratedCsv;
  String? _lastFileName;
  int _totalItems = 0;
  String? _cachedInventoryName;
  String? _errorMessage;

  late final CsvService _csvService;
  late final ReportGenerator _reportGenerator;
  late final ReportPreviewer _reportPreviewer;

  @override
  void initState() {
    super.initState();
    _csvService = CsvService();
    _reportGenerator = ReportGenerator(csvService: _csvService);
    _reportPreviewer = ReportPreviewer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFromProvider();
    });
  }

  void _initializeFromProvider() {
    if (!mounted) return;
    try {
      final provider = context.read<InventoryProvider>();
      _cachedInventoryName = provider.currentInventoryName;
      final settings = provider.currentSettings;
      if (settings != null) {
        for (var field in settings.activeFields) {
          _selectedFields.add(field.fieldName);
        }
      }
      _selectedFields.add('Inventory');
      setState(() {});
    } catch (e) {
      debugPrint('Error initializing report fields: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final availableFields = _getAvailableFields(provider);
    _cachedInventoryName = provider.currentInventoryName;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Generate Report', style: TextStyle(fontSize: 16)),
            Text(
              _cachedInventoryName ?? '',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
      body: _isGenerating
          ? ProgressView(
              progress: _progress,
              statusMessage: _statusMessage,
            )
          : _buildMainContent(availableFields, provider),
    );
  }

  Widget _buildMainContent(List<String> availableFields, InventoryProvider provider) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Error message
        if (_errorMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _errorMessage = null),
                ),
              ],
            ),
          ),
        
        ReportTypeCard(
          selectedType: _reportType,
          onTypeChanged: (type) => setState(() => _reportType = type),
        ),
        const SizedBox(height: 16),
        FieldSelectorCard(
          availableFields: availableFields,
          selectedFields: _selectedFields,
          onSelectionChanged: () => setState(() {}),
        ),
        const SizedBox(height: 24),
        ActionButtons(
          hasSelection: _selectedFields.isNotEmpty,
          onPreview: () => _previewReport(provider),
          onDownload: () => _generateAndSaveReport(provider),
        ),
        if (_lastGeneratedCsv != null) ...[
          const SizedBox(height: 16),
          GeneratedReportCard(
            fileName: _lastFileName,
            totalItems: _totalItems,
            csvData: _lastGeneratedCsv,
            onDownloadAgain: _downloadAgain,
            onCopyToClipboard: _copyToClipboard,
            csvService: _csvService,
          ),
        ],
        if (_previewData != null && _previewData!.isNotEmpty) ...[
          const SizedBox(height: 16),
          PreviewCard(
            previewData: _previewData!,
            totalItems: _totalItems,
            onClear: () => setState(() => _previewData = null),
          ),
        ],
      ],
    );
  }

  List<String> _getAvailableFields(InventoryProvider provider) {
    final fields = [
      'Name', 'Code', 'Barcode', 'Color', 'Material', 'Size',
      'Production Date', 'Expire Date', 'Note', 'Quantity', 'Label', 'Inventory',
    ];
    final settings = provider.currentSettings;
    if (settings != null) {
      fields.addAll(settings.customFieldNames);
    }
    return fields;
  }

  void _previewReport(InventoryProvider provider) {
    setState(() => _errorMessage = null);

    try {
      final result = _reportPreviewer.preview(
        provider: provider,
        reportType: _reportType,
        selectedFields: _selectedFields,
        inventoryName: _cachedInventoryName ?? 'Unknown',
      );

      if (result.error != null) {
        setState(() => _errorMessage = result.error);
        return;
      }

      setState(() {
        _previewData = result.data;
        _totalItems = result.totalItems;
      });

      if (result.message != null && mounted) {
        _showSnackBar(result.message!);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Preview failed: ${e.toString()}');
    }
  }

  Future<void> _generateAndSaveReport(InventoryProvider provider) async {
    setState(() {
      _isGenerating = true;
      _progress = 0;
      _statusMessage = 'Preparing data...';
      _errorMessage = null;
    });

    try {
      final result = await _reportGenerator.generateReport(
        provider: provider,
        reportType: _reportType,
        selectedFields: _selectedFields,
        inventoryName: _cachedInventoryName ?? 'Unknown',
        onProgress: (progress, message) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _statusMessage = message;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _lastGeneratedCsv = result.csvData;
          _lastFileName = result.fileName;
          _totalItems = result.totalItems;
          _previewData = null;
          _isGenerating = false;
        });

        if (result.filePath != null) {
          _showSnackBar('📊 Report saved: ${result.fileName}', duration: 4);
        } else {
          _showSnackBar('Report generated successfully');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _errorMessage = 'Failed to generate report: ${e.toString()}';
        });
      }
    }
  }

  void _downloadAgain() {
    if (_lastGeneratedCsv != null && _lastFileName != null) {
      try {
        _csvService.saveFile(_lastGeneratedCsv!, _lastFileName!);
        _showSnackBar('File downloaded again');
      } catch (e) {
        _showSnackBar('Download failed: ${e.toString()}', isError: true);
      }
    }
  }

  void _copyToClipboard() {
    if (_lastGeneratedCsv == null) return;
    Clipboard.setData(ClipboardData(text: _lastGeneratedCsv!));
    _showSnackBar('CSV data copied to clipboard');
  }

  void _showSnackBar(String message, {int duration = 3, bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : null,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
          margin: const EdgeInsets.all(20),
          duration: Duration(seconds: duration),
        ),
      );
  }
}