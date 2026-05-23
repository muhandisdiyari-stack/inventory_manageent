part of 'reports_bloc.dart';

sealed class ReportsEvent {
  const ReportsEvent();
}

class InitializeReportFields extends ReportsEvent {
  const InitializeReportFields();
}

class UpdateAvailableFields extends ReportsEvent {
  final List<String>? customFieldNames;
  const UpdateAvailableFields({this.customFieldNames});
}

class SetReportType extends ReportsEvent {
  final String reportType;
  const SetReportType(this.reportType);
}

class ToggleField extends ReportsEvent {
  final String fieldName;
  const ToggleField(this.fieldName);
}

class ResetFields extends ReportsEvent {
  const ResetFields();
}

class SelectAllFields extends ReportsEvent {
  const SelectAllFields();
}

class PreviewReport extends ReportsEvent {
  final List<InventoryItem> allItems;
  final String inventoryName;
  const PreviewReport({
    required this.allItems,
    required this.inventoryName,
  });
}

class GenerateReport extends ReportsEvent {
  final List<InventoryItem> allItems;
  final InventorySettings? settings;
  final String inventoryName;
  const GenerateReport({
    required this.allItems,
    this.settings,
    required this.inventoryName,
  });
}

class DownloadAgain extends ReportsEvent {
  const DownloadAgain();
}

class CopyToClipboard extends ReportsEvent {
  const CopyToClipboard();
}

class ClearReportMessages extends ReportsEvent {
  const ClearReportMessages();
}