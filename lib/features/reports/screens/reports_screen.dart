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
    // Ensure we have a preview data or create an empty one
    final previewData = _previewData;
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
        if (previewData != null && previewData.isNotEmpty) ...[
          const SizedBox(height: 16),
          PreviewCard(
            previewData: previewData,
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
      'Production Date', 'Expire Date', 'Note', 'Quantity', 'Label', 'Inventory'
    ];
    final settings = provider.currentSettings;
    if (settings != null) {
      fields.addAll(settings.customFieldNames);
    }
    return fields;
  }

  void _previewReport(InventoryProvider provider) {
    final result = _reportPreviewer.preview(
      provider: provider,
      reportType: _reportType,
      selectedFields: _selectedFields,
      inventoryName: _cachedInventoryName ?? 'Unknown',
    );
    
    if (result.error != null) {
      _showMessage(result.error!, isError: true);
      return;
    }
    
    setState(() {
      _previewData = result.data;
      _totalItems = result.totalItems;
    });
    
    if (result.message != null) {
      _showMessage(result.message!);
    }
  }

  Future<void> _generateAndSaveReport(InventoryProvider provider) async {
    setState(() {
      _isGenerating = true;
      _progress = 0;
      _statusMessage = 'Preparing data...';
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
          _showMessage('📊 Report saved: ${result.fileName}', duration: 4);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        _showMessage('Error: ${e.toString()}', isError: true);
      }
    }
  }

  void _downloadAgain() {
    if (_lastGeneratedCsv != null && _lastFileName != null) {
      _csvService.saveFile(_lastGeneratedCsv!, _lastFileName!);
    }
  }

  void _copyToClipboard() {
    if (_lastGeneratedCsv == null) return;
    Clipboard.setData(ClipboardData(text: _lastGeneratedCsv!));
    _showMessage('CSV data copied to clipboard');
  }

  void _showMessage(String message, {int duration = 3, bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
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