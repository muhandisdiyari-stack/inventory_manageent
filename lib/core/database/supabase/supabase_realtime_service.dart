import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../config/app_config.dart';

/// Handles Supabase Realtime subscriptions for live data synchronization.
///
/// Listens to PostgreSQL changes via Supabase Realtime and updates
/// the local Hive cache accordingly, then notifies the UI via callbacks.
class SupabaseRealtimeService {
  final SupabaseClient _client;
  final Map<String, StreamSubscription> _subscriptions = {};
  final Map<String, List<void Function()>> _listeners = {};

  SupabaseRealtimeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  bool get isEnabled => AppConfig.useSupabase;

  // ═══════════════════════════════════════════════════════════════
  // Subscription Management
  // ═══════════════════════════════════════════════════════════════

  /// Subscribe to inventory items changes for a specific inventory.
  void subscribeToInventoryItems(String inventoryId, {VoidCallback? onChange}) {
    if (!isEnabled) return;

    final channelName = 'items:$inventoryId';
    if (_subscriptions.containsKey(channelName)) return;

    try {
      final subscription = _client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'inventory_items',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'inventory_id',
              value: inventoryId,
            ),
            callback: (payload) {
              debugPrint('🔄 Realtime items change: ${payload.eventType}');
              _handleItemChange(inventoryId, payload);
              _notifyListeners(channelName);
            },
          )
          .subscribe();

      _subscriptions[channelName] = subscription as StreamSubscription<dynamic>;
      if (onChange != null) {
        _addListener(channelName, onChange);
      }
    } catch (e) {
      debugPrint('❌ Realtime items subscription failed: $e');
    }
  }

  /// Subscribe to labels changes for a specific inventory.
  void subscribeToLabels(String inventoryId, {VoidCallback? onChange}) {
    if (!isEnabled) return;

    final channelName = 'labels:$inventoryId';
    if (_subscriptions.containsKey(channelName)) return;

    try {
      final subscription = _client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'labels',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'inventory_id',
              value: inventoryId,
            ),
            callback: (payload) {
              debugPrint('🔄 Realtime labels change: ${payload.eventType}');
              _handleLabelChange(inventoryId, payload);
              _notifyListeners(channelName);
            },
          )
          .subscribe();

      _subscriptions[channelName] = subscription as StreamSubscription<dynamic>;
      if (onChange != null) {
        _addListener(channelName, onChange);
      }
    } catch (e) {
      debugPrint('❌ Realtime labels subscription failed: $e');
    }
  }

  /// Subscribe to inventory membership changes.
  void subscribeToInventoryMembers(String inventoryId, {VoidCallback? onChange}) {
    if (!isEnabled) return;

    final channelName = 'members:$inventoryId';
    if (_subscriptions.containsKey(channelName)) return;

    try {
      final subscription = _client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'inventory_members',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'inventory_id',
              value: inventoryId,
            ),
            callback: (payload) {
              debugPrint('🔄 Realtime members change: ${payload.eventType}');
              _notifyListeners(channelName);
            },
          )
          .subscribe();

      _subscriptions[channelName] = subscription as StreamSubscription<dynamic>;
      if (onChange != null) {
        _addListener(channelName, onChange);
      }
    } catch (e) {
      debugPrint('❌ Realtime members subscription failed: $e');
    }
  }

  /// Subscribe to activity log changes for a specific inventory.
  void subscribeToActivityLog(String inventoryId, {VoidCallback? onChange}) {
    if (!isEnabled) return;

    final channelName = 'activity:$inventoryId';
    if (_subscriptions.containsKey(channelName)) return;

    try {
      final subscription = _client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'activity_log',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'inventory_id',
              value: inventoryId,
            ),
            callback: (payload) {
              debugPrint('🔄 Realtime activity: ${payload.eventType}');
              _notifyListeners(channelName);
            },
          )
          .subscribe();

      _subscriptions[channelName] = subscription as StreamSubscription<dynamic>;
      if (onChange != null) {
        _addListener(channelName, onChange);
      }
    } catch (e) {
      debugPrint('❌ Realtime activity subscription failed: $e');
    }
  }

  /// Unsubscribe from a specific channel.
  void unsubscribe(String channelName) {
    _subscriptions[channelName]?.cancel();
    _subscriptions.remove(channelName);
    _listeners.remove(channelName);
  }

  /// Unsubscribe from all channels.
  void unsubscribeAll() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _listeners.clear();
  }

  /// Unsubscribe from all channels for a specific inventory.
  void unsubscribeFromInventory(String inventoryId) {
    unsubscribe('items:$inventoryId');
    unsubscribe('labels:$inventoryId');
    unsubscribe('members:$inventoryId');
    unsubscribe('activity:$inventoryId');
  }

  // ═══════════════════════════════════════════════════════════════
  // Cache Reconciliation
  // ═══════════════════════════════════════════════════════════════

  /// Handles inventory item changes from realtime events.
  /// Reconciles the Hive cache with the authoritative Supabase state.
  Future<void> _handleItemChange(
      String inventoryId, PostgresChangePayload payload) async {
    try {
      final box = await Hive.openBox('items_$inventoryId');
      final newRecord = payload.newRecord;

      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
          // New item added — add to cache if not already present
          if (newRecord != null && newRecord['id'] != null) {
            final existingKeys = box.keys.cast<int>();
            bool found = false;
            for (final key in existingKeys) {
              final item = box.get(key);
              if (item is Map && item['_supabase_id'] == newRecord['id']) {
                found = true;
                break;
              }
            }
            if (!found) {
              // Cache will be refreshed on next full sync
              debugPrint('📦 New item detected via realtime, cache will refresh');
            }
          }
          break;

        case PostgresChangeEvent.update:
          // Item updated — update cache entry if exists
          if (newRecord != null) {
            final existingKeys = box.keys.cast<int>();
            for (final key in existingKeys) {
              final item = box.get(key);
              if (item is Map &&
                  item['customFields'] is Map &&
                  (item['customFields'] as Map)['_supabase_id'] ==
                      newRecord['id']) {
                // Update the cached item with new values
                item['name'] = newRecord['name'] ?? item['name'];
                item['quantity'] = newRecord['quantity'] ?? item['quantity'];
                item['label'] = newRecord['label'] ?? item['label'];
                item['barcode'] = newRecord['barcode'] ?? item['barcode'];
                if (item['customFields'] is Map) {
                  (item['customFields'] as Map)['_row_version'] =
                      (newRecord['row_version'] ?? 1).toString();
                }
                await box.put(key, item);
                break;
              }
            }
          }
          break;

        case PostgresChangeEvent.delete:
          // Item soft-deleted — mark in cache
          if (payload.oldRecord != null) {
            final deletedId = payload.oldRecord['id'];
            final existingKeys = box.keys.cast<int>();
            for (final key in existingKeys) {
              final item = box.get(key);
              if (item is Map &&
                  item['customFields'] is Map &&
                  (item['customFields'] as Map)['_supabase_id'] == deletedId) {
                await box.delete(key);
                break;
              }
            }
          }
          break;

        default:
          break;
      }
    } catch (e) {
      debugPrint('❌ Cache reconciliation error: $e');
    }
  }

  /// Handles label changes from realtime events.
  Future<void> _handleLabelChange(
      String inventoryId, PostgresChangePayload payload) async {
    try {
      final box = await Hive.openBox('labels_$inventoryId');
      final cachedList =
          box.get('labels_cache', defaultValue: <Map>[]) as List;

      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
          if (payload.newRecord != null) {
            cachedList.add(Map<String, dynamic>.from(payload.newRecord));
            await box.put('labels_cache', cachedList);
          }
          break;
        case PostgresChangeEvent.update:
          if (payload.newRecord != null) {
            final idx = cachedList.indexWhere(
              (l) => l['id'] == payload.newRecord!['id'],
            );
            if (idx != -1) {
              cachedList[idx] = Map<String, dynamic>.from(payload.newRecord);
              await box.put('labels_cache', cachedList);
            }
          }
          break;
        case PostgresChangeEvent.delete:
          if (payload.oldRecord != null) {
            cachedList.removeWhere(
              (l) => l['id'] == payload.oldRecord!['id'],
            );
            await box.put('labels_cache', cachedList);
          }
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('❌ Label cache reconciliation error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Listener Management
  // ═══════════════════════════════════════════════════════════════

  void _addListener(String channelName, VoidCallback listener) {
    _listeners.putIfAbsent(channelName, () => []).add(listener);
  }

  void _notifyListeners(String channelName) {
    final listeners = _listeners[channelName];
    if (listeners != null) {
      for (final listener in listeners) {
        listener();
      }
    }
  }

  /// Add a generic listener for a channel.
  void addListener(String channelName, VoidCallback listener) {
    _addListener(channelName, listener);
  }

  /// Remove a listener from a channel.
  void removeListener(String channelName, VoidCallback listener) {
    _listeners[channelName]?.remove(listener);
  }

  void dispose() {
    unsubscribeAll();
  }
}