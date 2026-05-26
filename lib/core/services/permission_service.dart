import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/user.dart';

/// Service for device permissions and inventory-level user permissions.
class PermissionService {
  final SupabaseClient? _supabaseClient;

  PermissionService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient;

  SupabaseClient get _client => _supabaseClient ?? Supabase.instance.client;

  // ─── Device Permissions ────────────────────────────────────────

  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    final results = <Permission, PermissionStatus>{};
    try { results[Permission.camera] = await Permission.camera.request(); } catch (_) {}
    if (!kIsWeb) { try { results[Permission.storage] = await Permission.storage.request(); } catch (_) {} }
    if (!kIsWeb && Platform.isAndroid) {
      try { results[Permission.manageExternalStorage] = await Permission.manageExternalStorage.request(); } catch (_) {}
    }
    return results;
  }

  static Future<bool> hasCameraPermission() async {
    if (kIsWeb) return true;
    try { return await Permission.camera.isGranted; } catch (_) { return true; }
  }

  static Future<bool> hasStoragePermission() async {
    if (kIsWeb) return true;
    try { return await Permission.storage.isGranted || await Permission.manageExternalStorage.isGranted; } catch (_) { return true; }
  }

  // ─── Inventory Permissions ─────────────────────────────────────

  /// Fetches the current user's permissions for a specific inventory from Supabase.
  Future<InventoryPermissions> getInventoryPermissions(String inventoryId) async {
    if (!AppConfig.useSupabase) return InventoryPermissions.fromRole('owner');

    try {
      final result = await _client.rpc('get_user_inventory_permissions', params: {'p_inventory_id': inventoryId});

      if (result is Map) {
        return InventoryPermissions(
          canCreate: result['can_create'] as bool? ?? false,
          canUpdate: result['can_update'] as bool? ?? false,
          canDelete: result['can_delete'] as bool? ?? false,
          canExport: result['can_export'] as bool? ?? true,
          canViewActivity: result['can_view_activity'] as bool? ?? true,
          canManageSettings: result['can_manage_settings'] as bool? ?? false,
          role: result['role'] as String? ?? 'viewer',
        );
      }
      return const InventoryPermissions();
    } catch (e) {
      debugPrint('Error fetching inventory permissions: $e');
      return const InventoryPermissions();
    }
  }

  /// Invites a member to an inventory with specific permissions.
  Future<Map<String, dynamic>> inviteInventoryMember({
    required String inventoryId,
    required String companyId,
    required String email,
    required String inventoryRole,
    bool canCreate = false,
    bool canUpdate = false,
    bool canDelete = false,
    bool canExport = true,
    bool canViewActivity = true,
    bool canManageSettings = false,
  }) async {
    if (!AppConfig.useSupabase) {
      return {'success': false, 'message': 'Offline mode'};
    }

    try {
      final user = _client.auth.currentUser;
      if (user == null) return {'success': false, 'message': 'Not authenticated'};

      final result = await _client.rpc('invite_inventory_member', params: {
        'p_inventory_id': inventoryId,
        'p_company_id': companyId,
        'p_email': email.trim().toLowerCase(),
        'p_inventory_role': inventoryRole,
        'p_can_create': canCreate,
        'p_can_update': canUpdate,
        'p_can_delete': canDelete,
        'p_can_export': canExport,
        'p_can_view_activity': canViewActivity,
        'p_can_manage_settings': canManageSettings,
        'p_invited_by': user.id,
      });

      if (result is Map) return Map<String, dynamic>.from(result);
      return {'success': false, 'message': 'Unexpected response'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Updates an inventory member's permissions.
  Future<bool> updateMemberPermissions({
    required String memberId,
    required String inventoryId,
    String? inventoryRole,
    bool? canCreate,
    bool? canUpdate,
    bool? canDelete,
    bool? canExport,
    bool? canViewActivity,
    bool? canManageSettings,
  }) async {
    if (!AppConfig.useSupabase) return false;
    try {
      await _client.rpc('update_inventory_member_permissions', params: {
        'p_member_id': memberId,
        'p_inventory_id': inventoryId,
        'p_inventory_role': inventoryRole,
        'p_can_create': canCreate,
        'p_can_update': canUpdate,
        'p_can_delete': canDelete,
        'p_can_export': canExport,
        'p_can_view_activity': canViewActivity,
        'p_can_manage_settings': canManageSettings,
      });
      return true;
    } catch (e) {
      debugPrint('Update member permissions error: $e');
      return false;
    }
  }

  /// Removes a member from an inventory.
  Future<bool> removeMember({required String memberId, required String inventoryId}) async {
    if (!AppConfig.useSupabase) return false;
    try {
      await _client.rpc('remove_inventory_member', params: {
        'p_member_id': memberId, 'p_inventory_id': inventoryId,
      });
      return true;
    } catch (e) {
      debugPrint('Remove member error: $e');
      return false;
    }
  }

  /// Gets all members of an inventory.
  Future<List<Map<String, dynamic>>> getInventoryMembers(String inventoryId) async {
    if (!AppConfig.useSupabase) return [];
    try {
      final data = await _client.rpc('get_inventory_members', params: {'p_inventory_id': inventoryId});
      if (data is List) return List<Map<String, dynamic>>.from(data);
      return [];
    } catch (e) {
      debugPrint('Get inventory members error: $e');
      return [];
    }
  }
}