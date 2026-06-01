import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../config/app_config.dart';

/// Handles Supabase Realtime subscriptions for live data synchronization.
class SupabaseRealtimeService {
  final _client = Supabase.instance.client;

  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, List<void Function()>> _listeners = {};

  bool get isEnabled => AppConfig.useSupabase;

  // ═══════════════════════════════════════════════════════════════
  // Subscription Management
  // ═══════════════════════════════════════════════════════════════

  void subscribeToInventoryItems(
    String inventoryId, {
    VoidCallback? onChange,
  }) {
    final key = 'items_$inventoryId';
    _removeChannel(key);

    try {
      final channel = _client
          .channel(key)
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
              debugPrint('🔄 Realtime items: ${payload.eventType} for $inventoryId');
              _handleItemCacheUpdate(inventoryId, payload);
              _notifyListeners(key);
            },
          )
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint('❌ Items subscription error: $error');
            } else {
              debugPrint('✅ Items subscribed: $status for $inventoryId');
            }
          });

      _channels[key] = channel;
      if (onChange != null) {
        _addListener(key, onChange);
      }
    } catch (e) {
      debugPrint('❌ Items subscription failed: $e');
    }
  }

  void subscribeToLabels(
    String inventoryId, {
    VoidCallback? onChange,
  }) {
    final key = 'labels_$inventoryId';
    _removeChannel(key);

    try {
      final channel = _client
          .channel(key)
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
              debugPrint('🔄 Realtime labels: ${payload.eventType} for $inventoryId');
              _handleLabelCacheUpdate(inventoryId, payload);
              _notifyListeners(key);
            },
          )
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint('❌ Labels subscription error: $error');
            } else {
              debugPrint('✅ Labels subscribed: $status for $inventoryId');
            }
          });

      _channels[key] = channel;
      if (onChange != null) {
        _addListener(key, onChange);
      }
    } catch (e) {
      debugPrint('❌ Labels subscription failed: $e');
    }
  }

  void subscribeToInventoryMembers(
    String inventoryId, {
    VoidCallback? onChange,
  }) {
    final key = 'members_$inventoryId';
    _removeChannel(key);

    try {
      final channel = _client
          .channel(key)
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
              debugPrint('🔄 Realtime members: ${payload.eventType}');
              _notifyListeners(key);
            },
          )
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint('❌ Members subscription error: $error');
            } else {
              debugPrint('✅ Members subscribed: $status');
            }
          });

      _channels[key] = channel;
      if (onChange != null) {
        _addListener(key, onChange);
      }
    } catch (e) {
      debugPrint('❌ Members subscription failed: $e');
    }
  }

  void subscribeToActivityLog(
    String inventoryId, {
    VoidCallback? onChange,
  }) {
    final key = 'activity_$inventoryId';
    _removeChannel(key);

    try {
      final channel = _client
          .channel(key)
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
              debugPrint('🔄 Realtime activity for $inventoryId');
              _notifyListeners(key);
            },
          )
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint('❌ Activity subscription error: $error');
            } else {
              debugPrint('✅ Activity subscribed: $status');
            }
          });

      _channels[key] = channel;
      if (onChange != null) {
        _addListener(key, onChange);
      }
    } catch (e) {
      debugPrint('❌ Activity subscription failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Cache Updates from Realtime Events
  // ═══════════════════════════════════════════════════════════════

  Future<void> _handleItemCacheUpdate(
      String inventoryId, PostgresChangePayload payload) async {
    try {
      final box = await Hive.openBox('items_$inventoryId');

      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
          debugPrint('📦 New item detected via realtime');
          break;

        case PostgresChangeEvent.update:
          if (payload.newRecord['id'] != null) {
            final keys = box.keys.toList();
            for (final key in keys) {
              final item = box.get(key);
              if (item is Map &&
                  item['customFields'] is Map &&
                  (item['customFields'] as Map)['_supabase_id'] == payload.newRecord['id']) {
                // Update cache with new values
                item['name'] = payload.newRecord['name'] ?? item['name'];
                item['quantity'] = payload.newRecord['quantity'] ?? item['quantity'];
                item['label'] = payload.newRecord['label'] ?? item['label'];
                item['barcode'] = payload.newRecord['barcode'] ?? item['barcode'];
                item['code'] = payload.newRecord['code'] ?? item['code'];
                item['color'] = payload.newRecord['color'] ?? item['color'];
                item['material'] = payload.newRecord['material'] ?? item['material'];
                item['size'] = payload.newRecord['size'] ?? item['size'];
                item['note'] = payload.newRecord['note'] ?? item['note'];
                if (item['customFields'] is Map) {
                  (item['customFields'] as Map)['_row_version'] =
                      (payload.newRecord['row_version'] ?? 1).toString();
                }
                await box.put(key, item);
                break;
              }
            }
          }
          break;

        case PostgresChangeEvent.delete:
          if (payload.oldRecord['id'] != null) {
            final deletedId = payload.oldRecord['id'];
            final keys = box.keys.toList();
            for (final key in keys) {
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
      debugPrint('❌ Cache update error: $e');
    }
  }

  Future<void> _handleLabelCacheUpdate(
      String inventoryId, PostgresChangePayload payload) async {
    try {
      final box = await Hive.openBox('labels_$inventoryId');
      final cachedList = List<Map>.from(
        box.get('labels_cache', defaultValue: <Map>[]) as List,
      );

      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
          if (payload.newRecord['id'] != null) {
            final exists = cachedList.any((l) => l['id'] == payload.newRecord['id']);
            if (!exists) {
              cachedList.add(Map.from(payload.newRecord));
              await box.put('labels_cache', cachedList);
              // Update label names too
              final labelNames = cachedList.map((l) => l['name'] as String).toList();
              await box.put('label_names', labelNames);
            }
          }
          break;

        case PostgresChangeEvent.update:
          if (payload.newRecord['id'] != null) {
            final idx = cachedList.indexWhere(
              (l) => l['id'] == payload.newRecord['id'],
            );
            if (idx != -1) {
              cachedList[idx] = Map.from(payload.newRecord);
              await box.put('labels_cache', cachedList);
              final labelNames = cachedList.map((l) => l['name'] as String).toList();
              await box.put('label_names', labelNames);
            }
          }
          break;

        case PostgresChangeEvent.delete:
          if (payload.oldRecord['id'] != null) {
            cachedList.removeWhere((l) => l['id'] == payload.oldRecord['id']);
            await box.put('labels_cache', cachedList);
            final labelNames = cachedList.map((l) => l['name'] as String).toList();
            await box.put('label_names', labelNames);
          }
          break;

        default:
          break;
      }
    } catch (e) {
      debugPrint('❌ Label cache update error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Cleanup
  // ═══════════════════════════════════════════════════════════════

  void unsubscribeFromInventory(String inventoryId) {
    _removeChannel('items_$inventoryId');
    _removeChannel('labels_$inventoryId');
    _removeChannel('members_$inventoryId');
    _removeChannel('activity_$inventoryId');
  }

  void _removeChannel(String key) {
    final existing = _channels.remove(key);
    if (existing != null) {
      try {
        _client.removeChannel(existing);
      } catch (e) {
        debugPrint('⚠️ Error removing channel $key: $e');
      }
    }
    _listeners.remove(key);
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

  void addListener(String channelName, VoidCallback listener) {
    _addListener(channelName, listener);
  }

  void removeListener(String channelName, VoidCallback listener) {
    _listeners[channelName]?.remove(listener);
  }

  void dispose() {
    for (final channel in _channels.values) {
      try {
        _client.removeChannel(channel);
      } catch (_) {}
    }
    _channels.clear();
    _listeners.clear();
  }

  void subscribeToNotifications({
  VoidCallback? onChange,
}) {
  const key = 'user_notifications';
  _removeChannel(key);

  try {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final channel = _client
        .channel(key)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            debugPrint('🔔 New notification: ${payload.newRecord['message']}');
            _notifyListeners(key);
          },
        )
        .subscribe((status, [error]) {
          if (error != null) {
            debugPrint('❌ Notifications subscription error: $error');
          } else {
            debugPrint('✅ Notifications subscribed: $status');
          }
        });

    _channels[key] = channel;
    if (onChange != null) {
      _addListener(key, onChange);
    }
  } catch (e) {
    debugPrint('❌ Notifications subscription failed: $e');
  }
}
}