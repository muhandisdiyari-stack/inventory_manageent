import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';

/// Handles Supabase Realtime subscriptions for live data synchronization.
class SupabaseRealtimeService {
  final _client = Supabase.instance.client;

  // Track active channels by key so we can unsubscribe later
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

    // Remove existing channel for this key if any
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
              debugPrint('🔄 Realtime: items changed for $inventoryId');
              _notifyListeners(key);
            },
          )
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint('❌ Realtime items subscription error: $error');
            } else {
              debugPrint('✅ Realtime items subscribed: $status');
            }
          });

      _channels[key] = channel;
      if (onChange != null) {
        _addListener(key, onChange);
      }
    } catch (e) {
      debugPrint('❌ Realtime items subscription failed: $e');
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
              debugPrint('🔄 Realtime: labels changed for $inventoryId');
              _notifyListeners(key);
            },
          )
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint('❌ Realtime labels subscription error: $error');
            } else {
              debugPrint('✅ Realtime labels subscribed: $status');
            }
          });

      _channels[key] = channel;
      if (onChange != null) {
        _addListener(key, onChange);
      }
    } catch (e) {
      debugPrint('❌ Realtime labels subscription failed: $e');
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
              debugPrint('🔄 Realtime: members changed for $inventoryId');
              _notifyListeners(key);
            },
          )
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint('❌ Realtime members subscription error: $error');
            } else {
              debugPrint('✅ Realtime members subscribed: $status');
            }
          });

      _channels[key] = channel;
      if (onChange != null) {
        _addListener(key, onChange);
      }
    } catch (e) {
      debugPrint('❌ Realtime members subscription failed: $e');
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
              debugPrint('🔄 Realtime: activity for $inventoryId');
              _notifyListeners(key);
            },
          )
          .subscribe((status, [error]) {
            if (error != null) {
              debugPrint('❌ Realtime activity subscription error: $error');
            } else {
              debugPrint('✅ Realtime activity subscribed: $status');
            }
          });

      _channels[key] = channel;
      if (onChange != null) {
        _addListener(key, onChange);
      }
    } catch (e) {
      debugPrint('❌ Realtime activity subscription failed: $e');
    }
  }

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
}