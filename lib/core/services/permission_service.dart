import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../models/user.dart';

/// Service for checking user permissions at both company and inventory level.
///
/// Permissions are checked against:
/// 1. User's company-level role (owner, admin, manager, staff, viewer)
/// 2. User's inventory-level permissions (for invited members)
/// 3. Supabase Row-Level Security (enforced server-side)
class PermissionService {
  final SupabaseClient? _supabaseClient;

  PermissionService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient;

  SupabaseClient get _client =>
      _supabaseClient ?? Supabase.instance.client;

  // ─── Device Permissions ────────────────────────────────────────

  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    final results = <Permission, PermissionStatus>{};

    try {
      results[Permission.camera] = await Permission.camera.request();
    } catch (_) {
      results[Permission.camera] = PermissionStatus.denied;
    }

    if (!kIsWeb) {
      try {
        results[Permission.storage] = await Permission.storage.request();
      } catch (_) {
        results[Permission.storage] = PermissionStatus.denied;
      }
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        results[Permission.manageExternalStorage] =
            await Permission.manageExternalStorage.request();
      } catch (_) {
        results[Permission.manageExternalStorage] = PermissionStatus.denied;
      }
    }

    return results;
  }

  static Future<bool> hasCameraPermission() async {
    if (kIsWeb) return true;
    try {
      return await Permission.camera.isGranted;
    } catch (_) {
      return true; // Assume granted on error to avoid blocking
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

  // ─── Inventory Member Permissions ──────────────────────────────

  /// Fetches the current user's permissions for a specific inventory.
  ///
  /// Returns [InventoryPermissions] based on:
  /// 1. If user is the company owner/admin → full permissions
  /// 2. If user is an invited member → their assigned permissions
  /// 3. Otherwise → viewer-only permissions
  Future<InventoryPermissions> getInventoryPermissions(
      String inventoryId) async {
    if (!AppConfig.useSupabase) {
      return InventoryPermissions.owner; // Offline mode: full access
    }

    try {
      final user = _client.auth.currentUser;
      if (user == null) return InventoryPermissions.viewer;

      // Check if user is a member of this inventory
      final memberData = await _client
          .from('inventory_members')
          .select('permissions')
          .eq('user_id', user.id)
          .eq('inventory_id', inventoryId)
          .maybeSingle();

      if (memberData != null && memberData['permissions'] is Map) {
        return InventoryPermissions.fromJson(
            Map<String, dynamic>.from(memberData['permissions'] as Map));
      }

      // Check if user is the company owner/admin
      final profileData = await _client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (profileData != null) {
        final role = profileData['role']?.toString() ?? 'staff';
        if (role == 'owner' || role == 'admin') {
          return InventoryPermissions.owner;
        }
        return InventoryPermissions.fromRole(role);
      }

      return InventoryPermissions.viewer;
    } catch (e) {
      debugPrint('Error fetching inventory permissions: $e');
      return InventoryPermissions.viewer;
    }
  }

  /// Checks if the current user can perform [action] on [inventoryId].
  Future<bool> canPerformAction(
      String inventoryId, InventoryAction action) async {
    final permissions = await getInventoryPermissions(inventoryId);
    switch (action) {
      case InventoryAction.view:
        return permissions.canView;
      case InventoryAction.addItem:
        return permissions.canAddItems;
      case InventoryAction.removeItem:
        return permissions.canRemoveItems;
      case InventoryAction.updateItem:
        return permissions.canUpdateItems;
      case InventoryAction.deleteItem:
        return permissions.canDeleteItems;
      case InventoryAction.downloadReport:
        return permissions.canDownloadReports;
      case InventoryAction.viewActivity:
        return permissions.canViewActivity;
      case InventoryAction.changeSettings:
        return permissions.canChangeSettings;
    }
  }

  /// Checks if the current user can manage (invite/remove) members
  /// for the given inventory's company.
  Future<bool> canManageMembers(String inventoryId) async {
    if (!AppConfig.useSupabase) return true;

    try {
      final user = _client.auth.currentUser;
      if (user == null) return false;

      // Get the company ID for this inventory
      final invData = await _client
          .from('inventories')
          .select('company_id')
          .eq('id', inventoryId)
          .maybeSingle();

      if (invData == null) return false;
      final companyId = invData['company_id'] as String;

      // Check if user is owner or admin of the company
      final memberData = await _client
          .from('company_members')
          .select('role')
          .eq('user_id', user.id)
          .eq('company_id', companyId)
          .maybeSingle();

      if (memberData == null) return false;
      final role = memberData['role']?.toString() ?? 'staff';
      return role == 'owner' || role == 'admin';
    } catch (e) {
      debugPrint('Error checking member management permission: $e');
      return false;
    }
  }

  /// Invites a user to an inventory with specific permissions.
  Future<Map<String, dynamic>> inviteMember({
    required String inventoryId,
    required String email,
    required InventoryPermissions permissions,
    required String companyId,
  }) async {
    if (!AppConfig.useSupabase) {
      return {'success': false, 'message': 'Offline mode'};
    }

    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final result = await _client.rpc('invite_inventory_member', params: {
        'p_inventory_id': inventoryId,
        'p_company_id': companyId,
        'p_email': email.trim().toLowerCase(),
        'p_permissions': permissions.toSupabaseJson(),
        'p_invited_by': user.id,
      });

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {'success': false, 'message': 'Unexpected response'};
    } catch (e) {
      debugPrint('Invite member error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Updates an existing member's permissions.
  Future<bool> updateMemberPermissions({
    required String inventoryId,
    required String memberId,
    required InventoryPermissions permissions,
  }) async {
    if (!AppConfig.useSupabase) return false;

    try {
      await _client.from('inventory_members').update({
        'permissions': permissions.toSupabaseJson(),
      }).eq('id', memberId).eq('inventory_id', inventoryId);

      return true;
    } catch (e) {
      debugPrint('Update member permissions error: $e');
      return false;
    }
  }

  /// Removes a member from an inventory.
  Future<bool> removeMember({
    required String inventoryId,
    required String memberId,
  }) async {
    if (!AppConfig.useSupabase) return false;

    try {
      await _client
          .from('inventory_members')
          .delete()
          .eq('id', memberId)
          .eq('inventory_id', inventoryId);

      return true;
    } catch (e) {
      debugPrint('Remove member error: $e');
      return false;
    }
  }

  /// Gets all members of an inventory with their permissions.
  Future<List<Map<String, dynamic>>> getInventoryMembers(
      String inventoryId) async {
    if (!AppConfig.useSupabase) return [];

    try {
      final data = await _client
          .from('inventory_members')
          .select('id, user_id, display_name, email, permissions, joined_at')
          .eq('inventory_id', inventoryId)
          .order('joined_at', ascending: true);

      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Get inventory members error: $e');
      return [];
    }
  }
}