import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/activity_log_service.dart';
import '../../../core/models/activity_log_entry.dart';

part 'activity_log_event.dart';
part 'activity_log_state.dart';

class ActivityLogBloc extends Bloc<ActivityLogEvent, ActivityLogState> {
  final ActivityLogService _logService;

  ActivityLogBloc({required ActivityLogService logService})
      : _logService = logService,
        super(const ActivityLogState()) {
    on<LoadActivityLogs>(_onLoadLogs);
    on<SetSearchQuery>(_onSetSearchQuery);
    on<SetFilterInventory>(_onSetFilterInventory);
    on<SetFilterEntityType>(_onSetFilterEntityType);
    on<ToggleStatistics>(_onToggleStatistics);
    on<ExportActivityLogs>(_onExportLogs);
  }

  Future<void> _onLoadLogs(
      LoadActivityLogs event, Emitter<ActivityLogState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));

    try {
      await _logService.initialize();

      final allLogs = _logService.getLogs(
        inventoryId: state.filterInventoryId,
        entityType: state.filterEntityType,
      );

      final filteredLogs = allLogs.where((log) {
        if (state.searchQuery.isEmpty) return true;
        final q = state.searchQuery.toLowerCase();
        return log.entityName.toLowerCase().contains(q) ||
            (log.details?.toLowerCase().contains(q) ?? false) ||
            (log.inventoryName?.toLowerCase().contains(q) ?? false);
      }).toList();

      final statistics = _logService.getStatistics(
        inventoryId: state.filterInventoryId,
      );

      emit(state.copyWith(
        logs: filteredLogs,
        statistics: statistics,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _onSetSearchQuery(
      SetSearchQuery event, Emitter<ActivityLogState> emit) {
    emit(state.copyWith(searchQuery: event.query));
    add(const LoadActivityLogs());
  }

  void _onSetFilterInventory(
      SetFilterInventory event, Emitter<ActivityLogState> emit) {
    emit(state.copyWith(filterInventoryId: event.inventoryId));
    add(const LoadActivityLogs());
  }

  void _onSetFilterEntityType(
      SetFilterEntityType event, Emitter<ActivityLogState> emit) {
    emit(state.copyWith(filterEntityType: event.entityType));
    add(const LoadActivityLogs());
  }

  void _onToggleStatistics(
      ToggleStatistics event, Emitter<ActivityLogState> emit) {
    emit(state.copyWith(showStats: !state.showStats));
  }

  Future<void> _onExportLogs(
      ExportActivityLogs event, Emitter<ActivityLogState> emit) async {
    emit(state.copyWith(isLoading: true));

    try {
      final filePath = await _logService.saveLogsToFile(
        inventoryId: state.filterInventoryId,
      );
      emit(state.copyWith(
        isLoading: false,
        exportedFilePath: filePath,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}