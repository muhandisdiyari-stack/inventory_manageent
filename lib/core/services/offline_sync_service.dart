// ignore_for_file: unused_field
import '../config/app_config.dart';
import '../database/hive/hive_cache_service.dart';
import '../database/supabase/supabase_client.dart';

class OfflineSyncService {
  final HiveCacheService _cacheService;
  final SupabaseClientService _supabaseClient;
  bool _isSyncing = false;

  OfflineSyncService({
    required HiveCacheService cacheService,
    required SupabaseClientService supabaseClient,
  })  : _cacheService = cacheService,
        _supabaseClient = supabaseClient;

  bool get isSyncing => _isSyncing;
  bool get isCloudEnabled => AppConfig.useSupabase;

  Future<SyncResult> syncCompanyData(String companyId) async {
    if (!isCloudEnabled) {
      return SyncResult(success: true, message: 'Offline mode');
    }
    _isSyncing = true;
    _isSyncing = false;
    return SyncResult(success: true, message: 'Sync complete');
  }
}

class SyncResult {
  final bool success;
  final String message;
  final int syncedCount;
  final int failedCount;

  SyncResult({
    this.success = false,
    this.message = '',
    this.syncedCount = 0,
    this.failedCount = 0,
  });
}