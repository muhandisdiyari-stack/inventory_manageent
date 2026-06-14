import 'package:flutter/foundation.dart';
import 'package:inventory_management/features/inventory_management/models/inventory_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../config/app_config.dart';
import '../../models/label.dart';

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
      if (onChange != null) _addListener(key, onChange);
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
      if (onChange != null) _addListener(key, onChange);
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
      final channel = _client.channel(key).onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'inventory_members',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'inventory_id',
          value: inventoryId,
        ),
        callback: (payload) => _notifyListeners(key),
      ).subscribe((status, [error]) {
        if (error != null) { debugPrint('❌ Members subscription error: $error'); }
        else { debugPrint('✅ Members subscribed: $status'); }
      });
      _channels[key] = channel;
      if (onChange != null) _addListener(key, onChange);
    } catch (e) { debugPrint('❌ Members subscription failed: $e'); }
  }

  void subscribeToActivityLog(String inventoryId, {VoidCallback? onChange}) {
    final key = 'activity_$inventoryId';
    _removeChannel(key);
    try {
      final channel = _client.channel(key).onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'activity_log',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'inventory_id',
          value: inventoryId,
        ),
        callback: (payload) => _notifyListeners(key),
      ).subscribe((status, [error]) {
        if (error != null) { debugPrint('❌ Activity subscription error: $error'); }
        else { debugPrint('✅ Activity subscribed: $status'); }
      });
      _channels[key] = channel;
      if (onChange != null) _addListener(key, onChange);
    } catch (e) { debugPrint('❌ Activity subscription failed: $e'); }
  }

  // ═══════════════════════════════════════════════════════════════
  // Cache Updates
  // ═══════════════════════════════════════════════════════════════

  void _handleItemCacheUpdate(String inventoryId, PostgresChangePayload payload) {
    try {
      final boxName = 'items_$inventoryId';
      if (!Hive.isBoxOpen(boxName)) return;
      final box = Hive.box<InventoryItem>(boxName);

      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
          // FIXED: Actually add the new item from realtime event
          if (payload.newRecord['id'] != null && payload.newRecord['is_deleted'] != true) {
            final supabaseId = payload.newRecord['id'].toString();
            bool exists = false;
            for (final item in box.values) {
              if (item.supabaseId == supabaseId) { exists = true; break; }
            }
            if (!exists) {
              final item = InventoryItem(
                id: supabaseId,
                name: payload.newRecord['name']?.toString() ?? '',
                code: payload.newRecord['code']?.toString() ?? '',
                barcode: payload.newRecord['barcode']?.toString() ?? '',
                color: payload.newRecord['color']?.toString() ?? '',
                material: payload.newRecord['material']?.toString() ?? '',
                size: payload.newRecord['size']?.toString() ?? '',
                quantity: (payload.newRecord['quantity'] as int?) ?? 0,
                label: payload.newRecord['label']?.toString() ?? '',
                note: payload.newRecord['note']?.toString() ?? '',
              );
              item.supabaseId = supabaseId;
              item.inventoryId = inventoryId;
              item.companyId = payload.newRecord['company_id']?.toString();
              item.createdBy = payload.newRecord['created_by']?.toString();
              item.createdByName = payload.newRecord['created_by_name']?.toString();
              item.isSynced = true;
              item.createdAt = payload.newRecord['created_at'] != null
                  ? DateTime.parse(payload.newRecord['created_at'] as String)
                  : DateTime.now();
              item.modified = payload.newRecord['updated_at'] != null
                  ? DateTime.parse(payload.newRecord['updated_at'] as String)
                  : DateTime.now();
              box.add(item);
            }
          }
          break;

        case PostgresChangeEvent.update:
          if (payload.newRecord['id'] != null) {
            final supabaseId = payload.newRecord['id'].toString();
            final isDeleted = payload.newRecord['is_deleted'] == true;

            if (isDeleted) {
              final keys = box.keys.toList();
              for (final key in keys) {
                final item = box.get(key);
                if (item != null && item.supabaseId == supabaseId) {
                  box.delete(key);
                  break;
                }
              }
            } else {
              final keys = box.keys.toList();
              for (final key in keys) {
                final item = box.get(key);
                if (item != null && item.supabaseId == supabaseId) {
                  item.name = payload.newRecord['name']?.toString() ?? item.name;
                  item.quantity = (payload.newRecord['quantity'] as int?) ?? item.quantity;
                  item.label = payload.newRecord['label']?.toString() ?? item.label;
                  item.barcode = payload.newRecord['barcode']?.toString() ?? item.barcode;
                  item.code = payload.newRecord['code']?.toString() ?? item.code;
                  item.color = payload.newRecord['color']?.toString() ?? item.color;
                  item.material = payload.newRecord['material']?.toString() ?? item.material;
                  item.size = payload.newRecord['size']?.toString() ?? item.size;
                  item.note = payload.newRecord['note']?.toString() ?? item.note;
                  item.rowVersion = (payload.newRecord['row_version'] as int?) ?? item.rowVersion;
                  item.isSynced = true;
                  item.save();
                  break;
                }
              }
            }
          }
          break;

        case PostgresChangeEvent.delete:
          if (payload.oldRecord['id'] != null) {
            final deletedId = payload.oldRecord['id'].toString();
            final keys = box.keys.toList();
            for (final key in keys) {
              final item = box.get(key);
              if (item != null && item.supabaseId == deletedId) {
                box.delete(key);
                break;
              }
            }
          }
          break;

        default: break;
      }
    } catch (e) {
      debugPrint('❌ Cache update error: $e');
    }
  }

  void _handleLabelCacheUpdate(String inventoryId, PostgresChangePayload payload) {
    try {
      final boxName = 'labels_$inventoryId';
      if (!Hive.isBoxOpen(boxName)) return;
      final box = Hive.box(boxName);

      final label = Label.fromSupabase(Map<String, dynamic>.from(payload.newRecord));
      final cachedList = List<Map>.from(box.get('labels_cache', defaultValue: <Map>[]) as List);

      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
          if (!cachedList.any((l) => l['id'] == label.id)) {
            cachedList.add(label.toSupabaseJson());
            box.put('labels_cache', cachedList);
            box.put('label_names', cachedList.map((l) => l['name'] as String).toList());
          }
          break;
        case PostgresChangeEvent.update:
          final idx = cachedList.indexWhere((l) => l['id'] == label.id);
          if (idx != -1) {
            cachedList[idx] = label.toSupabaseJson();
            box.put('labels_cache', cachedList);
            box.put('label_names', cachedList.map((l) => l['name'] as String).toList());
          }
          break;
        case PostgresChangeEvent.delete:
          if (payload.oldRecord['id'] != null) {
            cachedList.removeWhere((l) => l['id'] == payload.oldRecord['id']);
            box.put('labels_cache', cachedList);
            box.put('label_names', cachedList.map((l) => l['name'] as String).toList());
          }
          break;
        default: break;
      }
    } catch (e) {
      debugPrint('❌ Label cache update error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Cleanup & Listeners
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
      try { _client.removeChannel(existing); } catch (e) { debugPrint('⚠️ Error removing channel $key: $e'); }
    }
    _listeners.remove(key);
  }

  void _addListener(String channelName, VoidCallback listener) {
    _listeners.putIfAbsent(channelName, () => []).add(listener);
  }

  void _notifyListeners(String channelName) {
    _listeners[channelName]?.forEach((listener) => listener());
  }

  void addListener(String channelName, VoidCallback listener) => _addListener(channelName, listener);
  void removeListener(String channelName, VoidCallback listener) => _listeners[channelName]?.remove(listener);

  void dispose() {
    for (final channel in _channels.values) { try { _client.removeChannel(channel); } catch (_) {} }
    _channels.clear();
    _listeners.clear();
  }
}