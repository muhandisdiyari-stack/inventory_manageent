part of 'activity_log_bloc.dart';

class ActivityLogState {
  final List<ActivityLogEntry> logs;
  final Map<String, dynamic> statistics;
  final bool isLoading;
  final bool showStats;
  final String? error;
  final String? exportedFilePath;
  final String? filterInventoryId;
  final String? filterEntityType;
  final String searchQuery;

  const ActivityLogState({
    this.logs = const [],
    this.statistics = const {},
    this.isLoading = false,
    this.showStats = false,
    this.error,
    this.exportedFilePath,
    this.filterInventoryId,
    this.filterEntityType,
    this.searchQuery = '',
  });

  ActivityLogState copyWith({
    List<ActivityLogEntry>? logs,
    Map<String, dynamic>? statistics,
    bool? isLoading,
    bool? showStats,
    String? error,
    String? exportedFilePath,
    String? filterInventoryId,
    String? filterEntityType,
    String? searchQuery,
  }) {
    return ActivityLogState(
      logs: logs ?? this.logs,
      statistics: statistics ?? this.statistics,
      isLoading: isLoading ?? this.isLoading,
      showStats: showStats ?? this.showStats,
      error: error,
      exportedFilePath: exportedFilePath ?? this.exportedFilePath,
      filterInventoryId: filterInventoryId ?? this.filterInventoryId,
      filterEntityType: filterEntityType ?? this.filterEntityType,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}