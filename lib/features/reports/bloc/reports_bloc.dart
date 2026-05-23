import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../inventory_management/models/inventory_item.dart';
import '../../inventory_management/models/inventory_settings.dart';
import '../services/csv_service.dart';
import '../features/report_generator.dart';
import '../features/report_previewer.dart';

part 'reports_event.dart';
part 'reports_state.dart';

class ReportsBloc extends Bloc<ReportsEvent, ReportsState> {
  final CsvService _csvService;
  late final ReportGenerator _reportGenerator;
  late final ReportPreviewer _reportPreviewer;

  ReportsBloc({required CsvService csvService})
      : _csvService = csvService,
        super(const ReportsState()) {
    _reportGenerator = ReportGenerator(csvService: _csvService);
    _reportPreviewer = ReportPreviewer();
    on<InitializeReportFields>(_onInitialize);
    on<UpdateAvailableFields>(_onUpdateAvailableFields);
    on<SetReportType>(_onSetReportType);
    on<ToggleField>(_onToggleField);
    on<ResetFields>(_onResetFields);
    on<SelectAllFields>(_onSelectAllFields);
    on<PreviewReport>(_onPreview);
    on<GenerateReport>(_onGenerate);
    on<DownloadAgain>(_onDownloadAgain);
    on<CopyToClipboard>(_onCopyToClipboard);
    on<ClearReportMessages>(_onClearMessages);
  }

  void _onInitialize(
      InitializeReportFields event, Emitter<ReportsState> emit) {
    final fields = [
      'Name', 'Code', 'Barcode', 'Color', 'Material', 'Size',
      'Production Date', 'Expire Date', 'Note', 'Quantity', 'Label',
      'Inventory',
    ];
    emit(state.copyWith(availableFields: fields));
  }

  void _onUpdateAvailableFields(
      UpdateAvailableFields event, Emitter<ReportsState> emit) {
    final fields = [
      'Name', 'Code', 'Barcode', 'Color', 'Material', 'Size',
      'Production Date', 'Expire Date', 'Note', 'Quantity', 'Label',
      'Inventory',
    ];
    if (event.customFieldNames != null) {
      fields.addAll(event.customFieldNames!);
    }
    emit(state.copyWith(availableFields: fields));
  }

  void _onSetReportType(
      SetReportType event, Emitter<ReportsState> emit) {
    emit(state.copyWith(
      reportType: event.reportType,
      previewData: null,
      generatedCsv: null,
      fileName: null,
      error: null,
    ));
  }

  void _onToggleField(
      ToggleField event, Emitter<ReportsState> emit) {
    if (event.fieldName == 'Inventory') return;
    final newFields = Set<String>.from(state.selectedFields);
    if (newFields.contains(event.fieldName)) {
      newFields.remove(event.fieldName);
    } else {
      newFields.add(event.fieldName);
    }
    emit(state.copyWith(selectedFields: newFields));
  }

  void _onResetFields(
      ResetFields event, Emitter<ReportsState> emit) {
    emit(state.copyWith(
      selectedFields: {'Name', 'Label', 'Quantity', 'Inventory'},
    ));
  }

  void _onSelectAllFields(
      SelectAllFields event, Emitter<ReportsState> emit) {
    emit(state.copyWith(
      selectedFields: Set<String>.from(state.availableFields),
    ));
  }

  void _onPreview(
      PreviewReport event, Emitter<ReportsState> emit) {
    emit(state.copyWith(error: null));

    try {
      if (event.allItems.isEmpty) {
        emit(state.copyWith(
          error: 'No items found for selected filter',
          previewData: null,
          totalItems: 0,
        ));
        return;
      }

      final result = _reportPreviewer.preview(
        allItems: event.allItems,
        reportType: state.reportType,
        selectedFields: state.selectedFields,
        inventoryName: event.inventoryName,
      );

      if (result.error != null) {
        emit(state.copyWith(error: result.error));
        return;
      }

      emit(state.copyWith(
        previewData: result.data,
        totalItems: result.totalItems,
      ));
    } catch (e) {
      emit(state.copyWith(error: 'Preview failed: ${e.toString()}'));
    }
  }

  Future<void> _onGenerate(
      GenerateReport event, Emitter<ReportsState> emit) async {
    if (event.allItems.isEmpty) {
      emit(state.copyWith(
        error: 'No items found for selected filter',
        isGenerating: false,
      ));
      return;
    }

    emit(state.copyWith(
      isGenerating: true,
      progress: 0,
      statusMessage: 'Preparing...',
      error: null,
    ));

    try {
      final result = await _reportGenerator.generateReport(
        allItems: event.allItems,
        settings: event.settings,
        reportType: state.reportType,
        selectedFields: state.selectedFields,
        inventoryName: event.inventoryName,
        onProgress: (progress, message) {
          if (!isClosed) {
            emit(state.copyWith(
              progress: progress,
              statusMessage: message,
            ));
          }
        },
      );

      if (!isClosed) {
        emit(state.copyWith(
          isGenerating: false,
          generatedCsv: result.csvData,
          fileName: result.fileName,
          totalItems: result.totalItems,
          previewData: null,
          progress: 1.0,
          statusMessage: result.filePath != null
              ? 'Complete!'
              : 'Saved locally',
        ));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(
          isGenerating: false,
          error: 'Failed to generate report: ${e.toString()}',
        ));
      }
    }
  }

  void _onDownloadAgain(
      DownloadAgain event, Emitter<ReportsState> emit) {
    if (state.generatedCsv != null && state.fileName != null) {
      try {
        _csvService.saveFile(state.generatedCsv!, state.fileName!);
        emit(state.copyWith(successMessage: 'File downloaded again'));
      } catch (e) {
        emit(state.copyWith(error: 'Download failed: ${e.toString()}'));
      }
    }
  }

  void _onCopyToClipboard(
      CopyToClipboard event, Emitter<ReportsState> emit) {
    if (state.generatedCsv != null) {
      Clipboard.setData(ClipboardData(text: state.generatedCsv!));
      emit(state.copyWith(successMessage: 'CSV data copied to clipboard'));
    }
  }

  void _onClearMessages(
      ClearReportMessages event, Emitter<ReportsState> emit) {
    emit(state.copyWith(
      error: null,
      successMessage: null,
    ));
  }
}