import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../inventory_management/bloc/inventory_bloc.dart';
import '../../inventory_management/models/inventory_item.dart';
import '../bloc/reports_bloc.dart';
import '../widgets/report_type_card.dart';
import '../widgets/field_selector_card.dart';
import '../widgets/action_buttons.dart';
import '../widgets/generated_report_card.dart';
import '../widgets/preview_card.dart';
import '../widgets/progress_view.dart';
import '../../../core/utils/snackbar_utils.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _fieldsInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ReportsBloc>().add(const InitializeReportFields());
        _syncCustomFields();
        final inventoryState = context.read<InventoryBloc>().state;
        if (inventoryState.inventoryId != null) {
          context.read<InventoryBloc>().add(
              LoadAllItems(inventoryState.inventoryId!));
        }
      }
    });
  }

  void _syncCustomFields() {
    if (_fieldsInitialized) return;
    final inventoryState = context.read<InventoryBloc>().state;
    final settings = inventoryState.settings;
    if (settings != null && settings.customFieldNames.isNotEmpty) {
      context.read<ReportsBloc>().add(
          UpdateAvailableFields(customFieldNames: settings.customFieldNames));
      _fieldsInitialized = true;
    }
  }

  List<InventoryItem> _getAllItems(InventoryState state) {
    if (state.allItems.isNotEmpty) return state.allItems;
    final allItems = <InventoryItem>[];
    allItems.addAll(state.currentItems);
    for (final result in state.searchResults) {
      final item = result['item'];
      if (item is InventoryItem && !allItems.contains(item)) {
        allItems.add(item);
      }
    }
    return allItems;
  }

  void _previewReport(
      InventoryState inventoryState, ReportsState reportsState) {
    final allItems = _getAllItems(inventoryState);

    if (allItems.isEmpty) {
      SnackBarUtils.show(context,
          message: 'No items found in this inventory',
          icon: Icons.info_outline);
      return;
    }

    if (reportsState.selectedFields.isEmpty) {
      SnackBarUtils.error(context, 'Please select at least one field');
      return;
    }

    context.read<ReportsBloc>().add(PreviewReport(
        allItems: allItems,
        inventoryName: inventoryState.inventoryName ?? 'Unknown'));
  }

  void _generateAndSaveReport(
      InventoryState inventoryState, ReportsState reportsState) {
    final allItems = _getAllItems(inventoryState);

    if (allItems.isEmpty) {
      SnackBarUtils.show(context,
          message: 'No items found for selected filter', isError: true);
      return;
    }

    context.read<ReportsBloc>().add(GenerateReport(
        allItems: allItems,
        settings: inventoryState.settings,
        inventoryName: inventoryState.inventoryName ?? 'Unknown'));
  }

  void _downloadAgain() {
    context.read<ReportsBloc>().add(const DownloadAgain());
  }

  void _copyToClipboard() {
    context.read<ReportsBloc>().add(const CopyToClipboard());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, inventoryState) {
        // FIXED: Try to sync custom fields once when settings become available
        if (inventoryState.isInitialized && !_fieldsInitialized) {
          // Use post-frame callback to avoid dispatching during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncCustomFields();
          });
        }

        final inventoryName = inventoryState.inventoryName ?? '';

        return BlocListener<ReportsBloc, ReportsState>(
          listener: (context, reportsState) {
            if (reportsState.successMessage != null) {
              if (!mounted) return;
              SnackBarUtils.success(context, reportsState.successMessage!);
              context.read<ReportsBloc>().add(const ClearReportMessages());
            }
            if (reportsState.error != null &&
                reportsState.generatedCsv == null &&
                reportsState.previewData == null) {
              if (!mounted) return;
              SnackBarUtils.error(context, reportsState.error!);
              context.read<ReportsBloc>().add(const ClearReportMessages());
            }
          },
          child: BlocBuilder<ReportsBloc, ReportsState>(
            builder: (context, reportsState) {
              if (reportsState.isGenerating) {
                return Scaffold(
                  appBar: AppBar(
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Generate Report',
                            style: TextStyle(fontSize: 16)),
                        Text(inventoryName,
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary)),
                      ],
                    ),
                  ),
                  body: ProgressView(
                    progress: reportsState.progress,
                    statusMessage: reportsState.statusMessage,
                  ),
                );
              }

              return Scaffold(
                appBar: AppBar(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Generate Report',
                          style: TextStyle(fontSize: 16)),
                      Text(inventoryName,
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                ),
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (reportsState.error != null &&
                        reportsState.generatedCsv == null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(reportsState.error!,
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 13)),
                          ),
                        ]),
                      ),
                    ReportTypeCard(
                      selectedType: reportsState.reportType,
                      onTypeChanged: (type) => context
                          .read<ReportsBloc>()
                          .add(SetReportType(type)),
                    ),
                    const SizedBox(height: 16),
                    FieldSelectorCard(
                      availableFields: reportsState.availableFields,
                      selectedFields: reportsState.selectedFields,
                      onSelectionChanged: () {},
                      onToggleField: (fieldName) => context
                          .read<ReportsBloc>()
                          .add(ToggleField(fieldName)),
                      onResetFields: () => context
                          .read<ReportsBloc>()
                          .add(const ResetFields()),
                      onSelectAllFields: () => context
                          .read<ReportsBloc>()
                          .add(const SelectAllFields()),
                    ),
                    const SizedBox(height: 24),
                    ActionButtons(
                      hasSelection: reportsState.selectedFields.isNotEmpty,
                      onPreview: () =>
                          _previewReport(inventoryState, reportsState),
                      onDownload: () => _generateAndSaveReport(
                          inventoryState, reportsState),
                    ),
                    if (reportsState.generatedCsv != null) ...[
                      const SizedBox(height: 16),
                      GeneratedReportCard(
                        fileName: reportsState.fileName,
                        totalItems: reportsState.totalItems,
                        csvData: reportsState.generatedCsv,
                        onDownloadAgain: _downloadAgain,
                        onCopyToClipboard: _copyToClipboard,
                        csvService: null,
                      ),
                    ],
                    if (reportsState.previewData != null &&
                        reportsState.previewData!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      PreviewCard(
                        previewData: reportsState.previewData!,
                        totalItems: reportsState.totalItems,
                        onClear: () => context
                            .read<ReportsBloc>()
                            .add(const ClearReportMessages()),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}