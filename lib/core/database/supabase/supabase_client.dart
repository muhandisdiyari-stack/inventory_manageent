import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';

String _getEmailRedirectTo() {
  if (kIsWeb) {
    final origin = Uri.base.origin;
    final path = Uri.base.path;
    if (path.length > 1) {
      return '$origin$path#/auth/callback';
    }
    return '$origin/#/auth/callback';
  }
  return 'inventory://auth/callback';
}

class SupabaseClientService {
  SupabaseClient? _client;
  bool _isInitialized = false;
  String? _lastError;

  bool get isConfigured => AppConfig.useSupabase && _isInitialized;
  String? get lastError => _lastError;

  SupabaseClientService() {
    if (AppConfig.useSupabase) {
      _initializeSupabase();
    } else {
      debugPrint('🔶 Running in offline mode.');
    }
  }

  void _initializeSupabase() {
    try {
      AppConfig.validate();
      _client = Supabase.instance.client;
      _isInitialized = true;
      _lastError = null;
      debugPrint('✅ Supabase client ready');
    } catch (e) {
      _lastError = e.toString();
      _isInitialized = false;
      _client = null;
      debugPrint('❌ Supabase initialization failed: $e');
      if (AppConfig.isProduction) {
        throw Exception('Failed to initialize Supabase in production: $e');
      }
    }
  }

  SupabaseClient get client {
    if (!_isInitialized || _client == null) {
      throw SupabaseNotInitializedException(
          _lastError ?? 'Supabase not initialized');
    }
    return _client!;
  }

  SupabaseClient? get safeClient =>
      (_isInitialized && _client != null) ? _client : null;

  // ─── Auth ─────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getCurrentUser() async {
    if (!isConfigured) return null;
    try {
      final user = _client!.auth.currentUser;
      if (user == null) return null;
      try {
        await _client!.auth.refreshSession();
      } catch (_) {
        return null;
      }
      return {
        'id': user.id,
        'email': user.email,
        'created_at': user.createdAt,
      };
    } catch (e) {
      debugPrint('Get current user error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> signIn(String email, String password) async {
    if (!isConfigured) return null;
    try {
      final response = await _client!.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 15));

      final user = response.user;
      if (user == null) return null;

      Map<String, dynamic>? profileData;
      try {
        profileData = await _client!
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
      } catch (e) {
        debugPrint('⚠️ Profile fetch error: $e');
      }

      return {
        'id': user.id,
        'email': user.email,
        'full_name':
            profileData?['full_name'] ?? user.userMetadata?['full_name'],
        'display_name':
            profileData?['display_name'] ?? user.userMetadata?['display_name'],
        'role': profileData?['role'] ?? 'viewer',
        'company_id': profileData?['company_id'],
        'is_approved': profileData?['is_approved'] ?? true,
        'email_confirmed': user.emailConfirmedAt != null,
        'created_at': user.createdAt,
      };
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('Sign in error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> signUp(
      String email, String password, String fullName) async {
    if (!isConfigured) return null;
    try {
      final redirectUrl = _getEmailRedirectTo();
      debugPrint('📧 signUp emailRedirectTo: $redirectUrl');

      final response = await _client!.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName, 'display_name': fullName},
        emailRedirectTo: redirectUrl,
      );

      final user = response.user;
      if (user == null) return null;

      final requiresConfirmation = response.session == null;

      return {
        'id': user.id,
        'email': user.email,
        'full_name': fullName,
        'display_name': fullName,
        'created_at': user.createdAt,
        'email_confirmed': !requiresConfirmation,
      };
    } on AuthException catch (e) {
      debugPrint('Sign up auth error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Sign up error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    if (!isConfigured) return;
    try {
      await _client!.auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
  }

  Future<bool> verifySession() async {
    if (!isConfigured) return false;
    try {
      final currentSession = _client!.auth.currentSession;
      if (currentSession == null) return false;

      final expiresAt = currentSession.expiresAt;
      final nowInSeconds =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

      if (expiresAt != null && expiresAt > nowInSeconds) {
        return true;
      }

      try {
        await _client!.auth.refreshSession();
        return _client!.auth.currentSession != null;
      } catch (_) {
        return _client!.auth.currentSession != null;
      }
    } catch (e) {
      debugPrint('Verify session error: $e');
      try {
        return _client!.auth.currentSession != null;
      } catch (_) {
        return false;
      }
    }
  }

  // ─── Company ──────────────────────────────────────────────────
  Future<Map<String, dynamic>?> createCompany(String name) async {
    if (!isConfigured) return null;
    try {
      final result =
          await _client!.rpc('create_company', params: {'p_name': name.trim()});
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (e) {
      debugPrint('Create company error: $e');
      rethrow;
    }
  }

  Future<bool> deleteCompanyCascade(String companyId) async {
    if (!isConfigured) return false;
    try {
      final result = await _client!
          .rpc('delete_company_cascade', params: {'p_company_id': companyId});
      return result is Map && result['success'] == true;
    } catch (e) {
      debugPrint('Delete company error: $e');
      return false;
    }
  }

  /// Returns companies where the user has membership.
  /// The database returns `is_owner` boolean. We map it to also include
  /// a synthetic `role` field for backward compatibility with existing UI.
  Future<List<Map<String, dynamic>>> getUserCompanies() async {
    if (!isConfigured) return [];
    try {
      final data = await _client!.rpc('get_user_companies');
      if (data is List) {
        return data.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final isOwner = map['is_owner'] == true;
          // Add synthetic 'role' field (the UI expects it)
          map['role'] = isOwner ? 'owner' : 'member';
          return map;
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get user companies error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getCompanyInventories(
      String companyId) async {
    if (!isConfigured) return [];
    try {
      final data = await _client!.rpc('get_company_inventories',
          params: {'p_company_id': companyId});
      if (data is List) {
        return data
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get company inventories error: $e');
      return [];
    }
  }

  // ─── Inventory Members ────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getInventoryMembers(
      String inventoryId) async {
    if (!isConfigured) return [];
    try {
      final data = await _client!.rpc('get_inventory_members',
          params: {'p_inventory_id': inventoryId});
      if (data is List) return List<Map<String, dynamic>>.from(data);
      return [];
    } catch (e) {
      debugPrint('Get inventory members error: $e');
      return [];
    }
  }

  /// Returns the current user's permissions in an inventory.
  /// The RPC returns a table (RETURNS TABLE) so Supabase returns a List.
  Future<Map<String, dynamic>?> getUserInventoryPermissions(
      String inventoryId) async {
    if (!isConfigured) return null;
    try {
      final result = await _client!.rpc('get_user_inventory_permissions',
          params: {'p_inventory_id': inventoryId});
      if (result is List && result.isNotEmpty) {
        return Map<String, dynamic>.from(result.first as Map);
      }
      return null;
    } catch (e) {
      debugPrint('Get user inventory permissions error: $e');
      return null;
    }
  }

  Future<bool> removeInventoryMember(
      String memberId, String inventoryId) async {
    if (!isConfigured) return false;
    try {
      final result = await _client!.rpc('remove_inventory_member', params: {
        'p_member_id': memberId,
        'p_inventory_id': inventoryId,
      });
      if (result is Map) return result['success'] == true;
      return false;
    } catch (e) {
      debugPrint('Remove inventory member error: $e');
      return false;
    }
  }

  Future<bool> updateInventoryMemberPermissions({
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
    if (!isConfigured) return false;
    try {
      final result = await _client!.rpc(
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
      debugPrint('Update inventory member permissions error: $e');
      return false;
    }
  }

  Future<bool> leaveInventory(String inventoryId) async {
    if (!isConfigured) return false;
    try {
      final result = await _client!
          .rpc('leave_inventory', params: {'p_inventory_id': inventoryId});
      if (result is Map) return result['success'] == true;
      return false;
    } catch (e) {
      debugPrint('Leave inventory error: $e');
      return false;
    }
  }

  Future<bool> deleteInventory(String inventoryId) async {
    if (!isConfigured) return false;
    try {
      final result = await _client!
          .rpc('delete_inventory', params: {'p_inventory_id': inventoryId});
      if (result is Map) return result['success'] == true;
      return false;
    } catch (e) {
      debugPrint('Delete inventory error: $e');
      return false;
    }
  }

  Future<bool> transferInventoryOwnership(
      String inventoryId, String newOwnerUserId) async {
    if (!isConfigured) return false;
    try {
      final result = await _client!.rpc('transfer_inventory_ownership',
          params: {
            'p_inventory_id': inventoryId,
            'p_new_owner_user_id': newOwnerUserId,
          });
      if (result is Map) return result['success'] == true;
      return false;
    } catch (e) {
      debugPrint('Transfer ownership error: $e');
      return false;
    }
  }

  // ─── Invitations ─────────────────────────────────────────────
  Future<Map<String, dynamic>?> createInvitation({
    required String companyId,
    required String inventoryId,
    required String email,
    required String role,
  }) async {
    if (!isConfigured) return null;
    try {
      final result = await _client!.rpc('create_invitation', params: {
        'p_company_id': companyId,
        'p_inventory_id': inventoryId,
        'p_email': email.trim().toLowerCase(),
        'p_role': role,
      });
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (e) {
      debugPrint('Create invitation error: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getPendingInvitations(
      String inventoryId) async {
    if (!isConfigured) return [];
    try {
      final data = await _client!.rpc('get_pending_invitations',
          params: {'p_inventory_id': inventoryId});
      if (data is List) {
        return data
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get pending invitations error: $e');
      return [];
    }
  }

  Future<bool> cancelInvitation(String invitationId) async {
    if (!isConfigured) return false;
    try {
      final result = await _client!
          .rpc('cancel_invitation', params: {'p_invitation_id': invitationId});
      if (result is Map) return result['success'] == true;
      return false;
    } catch (e) {
      debugPrint('Cancel invitation error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> acceptInvitation(String token) async {
    if (!isConfigured) return null;
    try {
      final result = await _client!
          .rpc('accept_invitation', params: {'p_token': token.trim()});
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (e) {
      debugPrint('Accept invitation error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> autoJoinPendingInvitations() async {
    if (!isConfigured) return null;
    try {
      final result = await _client!.rpc('auto_join_pending_invitations');
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (e) {
      debugPrint('Auto-join pending invitations error: $e');
      return null;
    }
  }

  // ─── Activity Log ────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getInventoryActivity({
    required String inventoryId,
    DateTime? cursor,
    int limit = 50,
  }) async {
    if (!isConfigured) return [];
    try {
      final data = await _client!.rpc('get_inventory_activity', params: {
        'p_inventory_id': inventoryId,
        'p_cursor': cursor?.toUtc().toIso8601String(),
        'p_limit': limit,
      });
      if (data is List) {
        return data
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get inventory activity error: $e');
      return [];
    }
  }

  /// Logs an activity entry. Resolves company_id from inventory.
  Future<void> logActivity({
    required String inventoryId,
    required String action,
    required String entityType,
    required String entityName,
    String? labelName,
    String? details,
    Map<String, dynamic>? changes,
  }) async {
    if (!isConfigured) return;
    try {
      // Fetch company_id from the inventory
      final invData = await _client!
          .from('inventories')
          .select('company_id')
          .eq('id', inventoryId)
          .maybeSingle();
      final companyId = invData?['company_id']?.toString();
      if (companyId == null) return;

      await _client!.rpc('log_activity', params: {
        'p_company_id': companyId,
        'p_inventory_id': inventoryId,
        'p_action': action,
        'p_entity_type': entityType,
        'p_entity_name': entityName,
        'p_label_name': labelName,
        'p_details': details,
        'p_changes': changes,
      });
    } catch (e) {
      debugPrint('Log activity error: $e');
    }
  }

  // ─── Chat ────────────────────────────────────────────────────
  Future<void> markChatRoomRead(String roomId) async {
    if (!isConfigured) return;
    try {
      await _client!.rpc('mark_chat_room_read', params: {
        'p_room_id': roomId,
      });
    } catch (e) {
      debugPrint('Mark chat room read error: $e');
    }
  }

  // ─── Profile ─────────────────────────────────────────────────
  Future<void> updateLastLogin() async {
    if (!isConfigured) return;
    try {
      await _client!.rpc('update_last_login');
    } catch (e) {
      debugPrint('Update last login error: $e');
    }
  }

  // ─── Notifications ───────────────────────────────────────────
  Future<bool> sendNotificationViaRpc({
    required String userId,
    required String title,
    required String message,
    String type = 'info',
  }) async {
    if (!isConfigured) return false;
    try {
      await _client!.rpc('send_notification', params: {
        'p_user_id': userId,
        'p_title': title,
        'p_message': message,
        'p_type': type,
      });
      return true;
    } catch (e) {
      debugPrint('Send notification error: $e');
      return false;
    }
  }

  // ─── Query helpers ────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> queryWithRLS(
    String table, {
    String? companyId,
    Map<String, dynamic>? filters,
  }) async {
    if (!isConfigured) return [];
    try {
      var query = _client!.from(table).select();
      if (companyId != null) query = query.eq('company_id', companyId);
      if (filters != null) {
        for (final entry in filters.entries) {
          query = query.eq(entry.key, entry.value);
        }
      }
      final data = await query;
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Query error: $e');
      return [];
    }
  }

  Future<bool> insertWithCompany(
      String table, Map<String, dynamic> data, String companyId) async {
    if (!isConfigured) return false;
    try {
      data['company_id'] = companyId;
      data['created_at'] = DateTime.now().toUtc().toIso8601String();
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _client!.from(table).insert(data);
      return true;
    } catch (e) {
      debugPrint('Insert error: $e');
      return false;
    }
  }

  Future<bool> update(
      String table, String id, Map<String, dynamic> data) async {
    if (!isConfigured) return false;
    try {
      data['updated_at'] = DateTime.now().toUtc().toIso8601String();
      await _client!.from(table).update(data).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Update error: $e');
      return false;
    }
  }

  Future<bool> softDelete(String table, String id) async {
    if (!isConfigured) return false;
    try {
      await _client!.from(table).update({
        'is_deleted': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Soft delete error: $e');
      return false;
    }
  }
}

class SupabaseNotInitializedException implements Exception {
  final String message;
  SupabaseNotInitializedException(this.message);

  @override
  String toString() => 'SupabaseNotInitializedException: $message';
}