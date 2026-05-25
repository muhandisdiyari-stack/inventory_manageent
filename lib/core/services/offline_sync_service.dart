import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../config/app_config.dart';
import '../database/supabase/supabase_client.dart';

/// Service for synchronizing data between local Hive cache and Supabase.
///
/// Supabase is authoritative; Hive is a read cache only.
/// On every sync, data is pulled from Supabase and overwrites Hive.
class OfflineSyncService {
  final SupabaseClientService _supabaseClient;
  bool _isSyncing = false;

  OfflineSyncService({
    required SupabaseClientService supabaseClient,
  }) : _supabaseClient = supabaseClient;

  bool get isSyncing => _isSyncing;
  bool get isCloudEnabled => AppConfig.useSupabase;

  /// Syncs all data for a company from Supabase to local cache.
  Future<SyncResult> syncCompanyData(String companyId) async {
    if (!isCloudEnabled) {
      return const SyncResult(
        success: true,
        message: 'Offline mode — nothing to sync',
      );
    }

    _isSyncing = true;

    try {
      final client = _supabaseClient.safeClient;
      if (client == null) {
        return const SyncResult(
          success: false,
          message: 'Supabase client not initialized',
        );
      }

      int syncedCount = 0;
      int failedCount = 0;

      // Sync inventories for this company
      try {
        final inventories = await client
            .from('inventories')
            .select()
            .eq('company_id', companyId)
            .eq('is_deleted', false);

        final inventoriesBox = await Hive.openBox('inventories_list');
        final cacheList = <Map<String, dynamic>>[];

        for (final inv in inventories) {
          try {
            cacheList.add(Map<String, dynamic>.from(inv));
            syncedCount++;
          } catch (_) {
            failedCount++;
          }
        }

        await inventoriesBox.put('cached_inventories', cacheList);
      } catch (e) {
        debugPrint('Inventory sync error: $e');
        failedCount++;
      }

      // Sync labels for this company
      try {
        final labels = await client
            .from('labels')
            .select()
            .eq('company_id', companyId)
            .eq('is_deleted', false);

        // Labels are cached per-inventory, so we just verify they exist
        syncedCount += labels.length;
      } catch (e) {
        debugPrint('Label sync error: $e');
      }

      _isSyncing = false;

      return SyncResult(
        success: true,
        message: 'Synced $syncedCount entities${failedCount > 0 ? ' ($failedCount failed)' : ''}',
        syncedCount: syncedCount,
        failedCount: failedCount,
      );
    } catch (e) {
      _isSyncing = false;
      return SyncResult(
        success: false,
        message: 'Sync failed: $e',
        failedCount: 1,
      );
    }
  }
}

/// Result of a sync operation.
class SyncResult {
  final bool success;
  final String message;
  final int syncedCount;
  final int failedCount;

  const SyncResult({
    required this.success,
    required this.message,
    this.syncedCount = 0,
    this.failedCount = 0,
  });
}