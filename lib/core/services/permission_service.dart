import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/user.dart';

class PermissionService {
  final SupabaseClient? _supabaseClient;

  PermissionService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient;

  SupabaseClient get _client => _supabaseClient ?? Supabase.instance.client;

  // ─── Device Permissions ───────────────────────────────────────

  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    final results = <Permission, PermissionStatus>{};
    try {
      results[Permission.camera] = await Permission.camera.request();
    } catch (_) {}
    if (!kIsWeb) {
      try {
        results[Permission.storage] = await Permission.storage.request();
      } catch (_) {}
    }
    if (!kIsWeb && Platform.isAndroid) {
      try {
        results[Permission.manageExternalStorage] =
            await Permission.manageExternalStorage.request();
      } catch (_) {}
    }
    return results;
  }

  static Future<bool> hasCameraPermission() async {
    if (kIsWeb) return true;
    try {
      return await Permission.camera.isGranted;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> hasStoragePermission() async {
    if (kIsWeb) return true;
    try {
      return await Permission.storage.isGranted ||
          await Permission.manageExternalStorage.isGranted;
    } catch (_) {
      return true;
    }
  }

  // ─── Inventory Permissions ────────────────────────────────────

  /// Get the current user's permissions for a specific inventory.
  /// This queries the `get_user_inventory_permissions` RPC which returns
  /// the user's role and all boolean permission flags from `inventory_members`.
  Future<InventoryPermissions> getInventoryPermissions(
      String inventoryId) async {
    if (!AppConfig.useSupabase) {
      return InventoryPermissions.fromRole('owner');
    }

    try {
      final result = await _client.rpc('get_user_inventory_permissions',
          params: {'p_inventory_id': inventoryId});

      if (result is Map) {
        return InventoryPermissions(
          canCreate: result['can_create'] as bool? ?? false,
          canUpdate: result['can_update'] as bool? ?? false,
          canDelete: result['can_delete'] as bool? ?? false,
          canExport: result['can_export'] as bool? ?? true,
          canViewActivity: result['can_view_activity'] as bool? ?? true,
          canManageSettings: result['can_manage_settings'] as bool? ?? false,
          canInviteMembers: result['can_invite_members'] as bool? ?? false,
          canRemoveMembers: result['can_remove_members'] as bool? ?? false,
          canManageLabels: result['can_manage_labels'] as bool? ?? false,
          canChat: result['can_chat'] as bool? ?? true,
          role: result['role'] as String? ?? 'viewer',
        );
      }
      return const InventoryPermissions();
    } catch (e) {
      debugPrint('Error fetching inventory permissions: $e');
      return const InventoryPermissions();
    }
  }

  /// Get all members of an inventory with their permissions.
  Future<List<Map<String, dynamic>>> getInventoryMembers(
      String inventoryId) async {
    if (!AppConfig.useSupabase) return [];
    try {
      final data = await _client.rpc('get_inventory_members',
          params: {'p_inventory_id': inventoryId});
      if (data is List) return List<Map<String, dynamic>>.from(data);
      return [];
    } catch (e) {
      debugPrint('Get inventory members error: $e');
      return [];
    }
  }

  /// Update a member's permissions in an inventory.
  Future<bool> updateMemberPermissions({
    required String memberId,
    required String inventoryId,
    String? role,
    bool? canCreate,
    bool? canUpdate,
    bool? canDelete,
    bool? canExport,
    bool? canViewActivity,
    bool? canManageSettings,
    bool? canInviteMembers,
    bool? canRemoveMembers,
    bool? canManageLabels,
    bool? canChat,
  }) async {
    if (!AppConfig.useSupabase) return false;
    try {
      final result = await _client.rpc(
          'update_inventory_member_permissions',
          params: {
            'p_member_id': memberId,
            'p_inventory_id': inventoryId,
            'p_role': role,
            'p_can_create': canCreate,
            'p_can_update': canUpdate,
            'p_can_delete': canDelete,
            'p_can_export': canExport,
            'p_can_view_activity': canViewActivity,
            'p_can_manage_settings': canManageSettings,
            'p_can_invite_members': canInviteMembers,
            'p_can_remove_members': canRemoveMembers,
            'p_can_manage_labels': canManageLabels,
            'p_can_chat': canChat,
          });
      if (result is Map) return result['success'] == true;
      return false;
    } catch (e) {
      debugPrint('Update member permissions error: $e');
      return false;
    }
  }

  /// Remove a member from an inventory.
  Future<bool> removeMember({
    required String memberId,
    required String inventoryId,
  }) async {
    if (!AppConfig.useSupabase) return false;
    try {
      final result = await _client.rpc('remove_inventory_member', params: {
        'p_member_id': memberId,
        'p_inventory_id': inventoryId,
      });
      if (result is Map) return result['success'] == true;
      return false;
    } catch (e) {
      debugPrint('Remove member error: $e');
      return false;
    }
  }
}