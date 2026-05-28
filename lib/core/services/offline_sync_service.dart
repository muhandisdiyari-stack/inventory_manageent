import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:inventory_management/core/constants/app_constants.dart';
import '../config/app_config.dart';
import '../database/supabase/supabase_client.dart';

/// Service for synchronizing data between local Hive cache and Supabase.
///
/// KEY PRINCIPLES:
/// - Supabase is ALWAYS authoritative
/// - Hive is a READ CACHE only
/// - On sync, data is pulled from Supabase and overwrites Hive
/// - Local changes are queued and pushed to Supabase, not committed locally first
/// - Cache is invalidated on realtime events
class OfflineSyncService {
  final SupabaseClientService _supabaseClient;
  bool _isSyncing = false;
  final List<Map<String, dynamic>> _pendingMutations = [];
  Timer? _retryTimer;

  OfflineSyncService({
    required SupabaseClientService supabaseClient,
  }) : _supabaseClient = supabaseClient;

  bool get isSyncing => _isSyncing;
  bool get isCloudEnabled => AppConfig.useSupabase;
  bool get hasPendingMutations => _pendingMutations.isNotEmpty;
  int get pendingCount => _pendingMutations.length;

  /// Syncs all data for a company from Supabase to local cache.
  /// This is a FULL REPLACEMENT of cache data — Supabase is authoritative.
  Future<SyncResult> syncCompanyData(String companyId) async {
    if (!isCloudEnabled) {
      return const SyncResult(
        success: true,
        message: 'Offline mode — nothing to sync',
      );
    }

    if (_isSyncing) {
      return const SyncResult(
        success: false,
        message: 'Sync already in progress',
      );
    }

    _isSyncing = true;

    try {
      final client = _supabaseClient.safeClient;
      if (client == null) {
        _isSyncing = false;
        return const SyncResult(
          success: false,
          message: 'Supabase client not initialized',
        );
      }

      int syncedCount = 0;
      int failedCount = 0;

      // 1. Sync inventories for this company
      try {
        final inventories = await client
            .from('inventories')
            .select()
            .eq('company_id', companyId)
            .eq('is_deleted', false)
            .order('created_at', ascending: false);

        final inventoriesBox =
            await Hive.openBox(AppConstants.inventoriesListBox);
        final cacheList = <Map<String, dynamic>>[];

        for (final inv in inventories) {
          try {
            cacheList.add(Map<String, dynamic>.from(inv));
            syncedCount++;
          } catch (_) {
            failedCount++;
          }
        }

        // Replace entire cache with authoritative data
        await inventoriesBox.put('cached_inventories', cacheList);
      } catch (e) {
        debugPrint('Inventory sync error: $e');
        failedCount++;
      }

      // 2. Sync labels for this company (per-inventory)
      try {
        final labels = await client
            .from('labels')
            .select()
            .eq('company_id', companyId)
            .eq('is_deleted', false)
            .order('name');

        // Group labels by inventory_id
        final labelsByInventory = <String, List<Map<String, dynamic>>>{};
        for (final label in labels) {
          final invId = label['inventory_id']?.toString() ?? '';
          labelsByInventory.putIfAbsent(invId, () => []).add(
              Map<String, dynamic>.from(label));
        }

        // Update each inventory's label cache
        for (final entry in labelsByInventory.entries) {
          try {
            final box = await Hive.openBox('labels_${entry.key}');
            await box.put('labels_cache', entry.value);
            await box.put('label_names',
                entry.value.map((l) => l['name']).toList());
            syncedCount += entry.value.length;
          } catch (_) {
            failedCount++;
          }
        }
      } catch (e) {
        debugPrint('Label sync error: $e');
      }

      _isSyncing = false;

      return SyncResult(
        success: true,
        message:
            'Synced $syncedCount entities${failedCount > 0 ? ' ($failedCount failed)' : ''}',
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

  // ═══════════════════════════════════════════════════════════════
  // Offline Mutation Queue
  // ═══════════════════════════════════════════════════════════════

  /// Queue a mutation for later sync when offline.
  /// Mutations are stored with a unique key to prevent duplicates.
  Future<void> queueMutation({
    required String mutationKey,
    required String table,
    required Map<String, dynamic> data,
    required String operation, // 'insert', 'update', 'delete'
  }) async {
    // Check if mutation with this key already exists
    final existing =
        _pendingMutations.indexWhere((m) => m['mutation_key'] == mutationKey);
    if (existing != -1) {
      _pendingMutations[existing] = {
        'mutation_key': mutationKey,
        'table': table,
        'data': data,
        'operation': operation,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
    } else {
      _pendingMutations.add({
        'mutation_key': mutationKey,
        'table': table,
        'data': data,
        'operation': operation,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
    }

    // Persist queue to Hive
    await _persistQueue();
  }

  /// Process all pending mutations.
  /// Uses idempotent operations where possible to prevent duplicates.
  Future<SyncResult> processPendingMutations() async {
    if (!isCloudEnabled || _pendingMutations.isEmpty) {
      return const SyncResult(success: true, message: 'No pending mutations');
    }

    final client = _supabaseClient.safeClient;
    if (client == null) {
      return const SyncResult(
        success: false,
        message: 'Cannot sync — offline',
      );
    }

    int successCount = 0;
    int failedCount = 0;
    final failedMutations = <Map<String, dynamic>>[];

    for (final mutation in List<Map<String, dynamic>>.from(_pendingMutations)) {
      try {
        final table = mutation['table'] as String;
        final data = Map<String, dynamic>.from(mutation['data'] as Map);
        final operation = mutation['operation'] as String;

        switch (operation) {
          case 'insert':
            await client.from(table).upsert(data);
            break;
          case 'update':
            final id = data.remove('id') as String?;
            if (id != null) {
              await client.from(table).update(data).eq('id', id);
            }
            break;
          case 'delete':
            final id = data['id'] as String?;
            if (id != null) {
              await client.from(table).update({
                'is_deleted': true,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              }).eq('id', id);
            }
            break;
        }

        _pendingMutations.remove(mutation);
        successCount++;
      } catch (e) {
        failedCount++;
        failedMutations.add(mutation);
        debugPrint('Mutation failed: $e');
      }
    }

    await _persistQueue();

    if (failedCount > 0 && successCount == 0) {
      // Schedule retry
      _scheduleRetry();
    }

    return SyncResult(
      success: failedCount == 0,
      message:
          'Processed $successCount mutations${failedCount > 0 ? ' ($failedCount failed — will retry)' : ''}',
      syncedCount: successCount,
      failedCount: failedCount,
    );
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 30), () {
      processPendingMutations();
    });
  }

  Future<void> _persistQueue() async {
    try {
      final box = await Hive.openBox(AppConstants.appSettingsBox);
      await box.put('pending_mutations', jsonEncode(_pendingMutations));
    } catch (_) {}
  }

  Future<void> loadPendingMutations() async {
    try {
      final box = await Hive.openBox(AppConstants.appSettingsBox);
      final raw = box.get('pending_mutations');
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        _pendingMutations.clear();
        _pendingMutations.addAll(decoded.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }

  void dispose() {
    _retryTimer?.cancel();
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