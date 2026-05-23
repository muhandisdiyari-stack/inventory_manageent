part of 'activity_log_bloc.dart';

sealed class ActivityLogEvent {
  const ActivityLogEvent();
}

class LoadActivityLogs extends ActivityLogEvent {
  const LoadActivityLogs();
}

class SetSearchQuery extends ActivityLogEvent {
  final String query;
  const SetSearchQuery(this.query);
}

class SetFilterInventory extends ActivityLogEvent {
  final String? inventoryId;
  const SetFilterInventory(this.inventoryId);
}

class SetFilterEntityType extends ActivityLogEvent {
  final String? entityType;
  const SetFilterEntityType(this.entityType);
}

class ToggleStatistics extends ActivityLogEvent {
  const ToggleStatistics();
}

class ExportActivityLogs extends ActivityLogEvent {
  const ExportActivityLogs();
}