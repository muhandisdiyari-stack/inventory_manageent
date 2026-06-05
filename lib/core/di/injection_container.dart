import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/theme/bloc/theme_bloc.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/company/bloc/company_bloc.dart';
import '../../features/inventory_selection/bloc/inventory_list_bloc.dart';
import '../../features/inventory_management/bloc/inventory_bloc.dart';
import '../../features/admin/bloc/admin_bloc.dart';
import '../../features/reports/bloc/reports_bloc.dart';
import '../../features/activity_log/bloc/activity_log_bloc.dart';
import '../../features/chat/bloc/unread_count_cubit.dart';
import '../services/auth_service.dart';
import '../services/admin_service.dart';
import '../services/activity_log_service.dart';
import '../services/offline_sync_service.dart';
import '../../features/inventory_management/services/inventory_service.dart';
import '../../features/reports/services/csv_service.dart';
import '../database/supabase/supabase_client.dart';
import '../database/supabase/supabase_realtime_service.dart';

/// Central dependency injection container.
///
/// All services and BLoCs are created here to ensure consistent dependency
/// injection throughout the app.
class InjectionContainer {
  // ─── Services ──────────────────────────────────────────────────

  static final SupabaseClientService supabaseClient =
      SupabaseClientService();

  static late final SupabaseRealtimeService realtimeService;

  static final AuthService authService = AuthService(
    supabaseClient: supabaseClient,
  );

  static final AdminService adminService = AdminService(
    client: supabaseClient.safeClient,
  );

  static final ActivityLogService logService = ActivityLogService();

  static final InventoryService inventoryService = InventoryService();

  static final CsvService csvService = CsvService();

  static late final OfflineSyncService offlineSyncService;

  // ─── Initialization ────────────────────────────────────────────

  static Future<void> initialize() async {
    // Initialize realtime service
    realtimeService = SupabaseRealtimeService();

    // Initialize offline sync service
    offlineSyncService = OfflineSyncService(
      supabaseClient: supabaseClient,
    );
    await offlineSyncService.loadPendingMutations();

    // Initialize other services
    await logService.initialize();
    await authService.initialize();

    // Process any pending offline mutations
    if (offlineSyncService.hasPendingMutations) {
      offlineSyncService.processPendingMutations();
    }
  }

  // ─── BLoC Providers ────────────────────────────────────────────

  static List<BlocProvider> get blocProviders {
    return [
      BlocProvider<ThemeBloc>(
        create: (_) => ThemeBloc(),
      ),
      BlocProvider<ActivityLogBloc>(
        create: (_) => ActivityLogBloc(logService: logService),
      ),
      BlocProvider<AuthBloc>(
        create: (_) => AuthBloc(
          authService: authService,
          adminService: adminService,
        ),
      ),
      BlocProvider<CompanyBloc>(
        create: (_) => CompanyBloc(authService: authService),
      ),
      BlocProvider<InventoryListBloc>(
        create: (_) => InventoryListBloc(
          inventoryService: inventoryService,
          logService: logService,
        ),
      ),
      BlocProvider<InventoryBloc>(
        create: (_) => InventoryBloc(
          inventoryService: inventoryService,
          realtimeService: realtimeService,
        ),
      ),
      BlocProvider<AdminBloc>(
        create: (_) => AdminBloc(adminService: adminService),
      ),
      BlocProvider<ReportsBloc>(
        create: (_) => ReportsBloc(csvService: csvService),
      ),
      BlocProvider<UnreadCountCubit>(
        create: (_) => UnreadCountCubit(),
      ),
    ];
  }

  /// Dispose all services.
  static void dispose() {
    realtimeService.dispose();
    offlineSyncService.dispose();
  }
}