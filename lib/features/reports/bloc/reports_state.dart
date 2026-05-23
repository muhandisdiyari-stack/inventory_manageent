part of 'reports_bloc.dart';

class ReportsState {
  final Set<String> selectedFields;
  final List<String> availableFields;
  final String reportType;
  final bool isGenerating;
  final double progress;
  final String? statusMessage;
  final List<List<dynamic>>? previewData;
  final String? generatedCsv;
  final String? fileName;
  final int totalItems;
  final String? error;
  final String? successMessage;
  final String? inventoryName;

  const ReportsState({
    this.selectedFields = const {
      'Name', 'Code', 'Label', 'Quantity', 'Inventory'
    },
    this.availableFields = const [],
    this.reportType = 'all',
    this.isGenerating = false,
    this.progress = 0,
    this.statusMessage,
    this.previewData,
    this.generatedCsv,
    this.fileName,
    this.totalItems = 0,
    this.error,
    this.successMessage,
    this.inventoryName,
  });

  ReportsState copyWith({
    Set<String>? selectedFields,
    List<String>? availableFields,
    String? reportType,
    bool? isGenerating,
    double? progress,
    String? statusMessage,
    List<List<dynamic>>? previewData,
    String? generatedCsv,
    String? fileName,
    int? totalItems,
    String? error,
    String? successMessage,
    String? inventoryName,
  }) {
    return ReportsState(
      selectedFields: selectedFields ?? this.selectedFields,
      availableFields: availableFields ?? this.availableFields,
      reportType: reportType ?? this.reportType,
      isGenerating: isGenerating ?? this.isGenerating,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      previewData: previewData ?? this.previewData,
      generatedCsv: generatedCsv ?? this.generatedCsv,
      fileName: fileName ?? this.fileName,
      totalItems: totalItems ?? this.totalItems,
      error: error,
      successMessage: successMessage,
      inventoryName: inventoryName ?? this.inventoryName,
    );
  }
}