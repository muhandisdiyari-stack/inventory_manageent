import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../database/supabase/supabase_client.dart';
import '../models/user.dart';
import '../config/app_config.dart';

class RegistrationResult {
  final bool success;
  final bool requiresEmailConfirmation;
  final String? email;
  final String? error;

  const RegistrationResult({
    required this.success,
    this.requiresEmailConfirmation = false,
    this.email,
    this.error,
  });
}

class AuthService {
  final SupabaseClientService _supabaseClient;

  User? _currentUser;
  bool _isAuthenticated = false;
  bool _emailConfirmed = false;

  AuthService({required SupabaseClientService supabaseClient})
      : _supabaseClient = supabaseClient;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isEmailConfirmed => _emailConfirmed;
  bool get requiresAuth => AppConfig.requiresAuth;

  set currentUser(User? user) {
    _currentUser = user;
  }

  set isAuthenticatedValue(bool value) {
    _isAuthenticated = value;
  }

  Future<void> initialize() async {
    debugPrint('🔍 AuthService.initialize() called');

    if (!requiresAuth && AppConfig.isDevelopment) {
      _currentUser = User(
        id: 'local_user',
        email: 'local@inventory.pro',
        displayName: 'Local User',
        role: UserRole.owner,
        isApproved: true,
        createdAt: DateTime.now(),
      );
      _isAuthenticated = true;
      _emailConfirmed = true;
      return;
    }

    if (!requiresAuth) {
      _isAuthenticated = false;
      return;
    }

    try {
      final authBox = await Hive.openBox('auth');
      final cachedData = authBox.get('current_user');

      if (cachedData is Map) {
        _currentUser =
            User.fromLocalJson(Map<String, dynamic>.from(cachedData));
        _emailConfirmed = authBox
                .get('email_confirmed', defaultValue: false) as bool? ??
            false;

        if (AppConfig.useSupabase) {
          try {
            final isValid = await _supabaseClient.verifySession();
            if (!isValid) {
              await _clearCache();
              _isAuthenticated = false;
              _currentUser = null;
            } else {
              _isAuthenticated = true;
            }
          } catch (e) {
            if (_currentUser != null) {
              _isAuthenticated = true;
            } else {
              _isAuthenticated = false;
            }
          }
        } else {
          _isAuthenticated = true;
        }
      } else {
        _isAuthenticated = false;
      }
    } catch (e) {
      debugPrint('❌ AuthService.initialize error: $e');
      _isAuthenticated = false;
    }
  }

  Future<List<Map<String, dynamic>>> getUserCompanies() async {
    return await _supabaseClient.getUserCompanies();
  }

  Future<bool> signIn(String email, String password) async {
    if (!requiresAuth) {
      _currentUser = User(
        id: email.hashCode.toString(),
        email: email,
        role: UserRole.dataOperator,
        isApproved: true,
        createdAt: DateTime.now(),
      );
      _isAuthenticated = true;
      _emailConfirmed = true;
      await _cacheCurrentUser();
      return true;
    }

    try {
      final userData = await _supabaseClient.signIn(email, password);

      if (userData != null) {
        _currentUser = User.fromCloudJson(userData);
        _isAuthenticated = true;
        _emailConfirmed = userData['email_confirmed'] as bool? ?? true;

        if (!(userData['is_approved'] as bool? ?? false)) {
          _currentUser = null;
          _isAuthenticated = false;
          await _clearCache();
          return false;
        }

        await _cacheCurrentUser();
        return true;
      }
      return false;
    } on AuthException catch (e) {
      debugPrint('❌ AuthException: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ signIn error: $e');
      return false;
    }
  }

  Future<RegistrationResult> register(
      String email, String password, String displayName) async {
    if (!requiresAuth) {
      _currentUser = User(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        email: email,
        displayName: displayName,
        role: UserRole.dataOperator,
        isApproved: false,
        createdAt: DateTime.now(),
      );
      _isAuthenticated = true;
      _emailConfirmed = true;
      await _cacheCurrentUser();
      return const RegistrationResult(
          success: true, requiresEmailConfirmation: false);
    }

    try {
      final userData =
          await _supabaseClient.signUp(email, password, displayName);

      if (userData == null) {
        return const RegistrationResult(
            success: false, error: 'Registration failed.');
      }

      if (!(userData['email_confirmed'] as bool? ?? false)) {
        return RegistrationResult(
            success: true, requiresEmailConfirmation: true, email: email);
      }

      _currentUser = User.fromCloudJson(userData);
      _isAuthenticated = true;
      _emailConfirmed = true;
      await _cacheCurrentUser();
      return const RegistrationResult(
          success: true, requiresEmailConfirmation: false);
    } on AuthException catch (e) {
      return RegistrationResult(success: false, error: e.message);
    } catch (e) {
      return RegistrationResult(success: false, error: e.toString());
    }
  }

  Future<void> signOut() async {
    _currentUser = null;
    _isAuthenticated = false;
    _emailConfirmed = false;
    await _supabaseClient.signOut();
    await _clearCache();
  }

  /// Check a specific permission in an inventory permissions map.
  bool hasInventoryPermission(Map<String, dynamic> permissions, String key) {
    return permissions[key] == true;
  }

  // ─── Company Operations ──────────────────────────────────────
  Future<Map<String, dynamic>?> createCompany(String name) async =>
      await _supabaseClient.createCompany(name);

  Future<bool> deleteCompany(String companyId) async =>
      await _supabaseClient.deleteCompanyCascade(companyId);

  Future<Map<String, dynamic>?> getUserCompany() async {
    final companies = await _supabaseClient.getUserCompanies();
    if (companies.isNotEmpty) return companies.first;
    return null;
  }

  // ─── Inventory Member Operations ─────────────────────────────
  Future<List<Map<String, dynamic>>> getInventoryMembers(
          String inventoryId) async =>
      await _supabaseClient.getInventoryMembers(inventoryId);

  Future<Map<String, dynamic>?> getUserInventoryPermissions(
          String inventoryId) async =>
      await _supabaseClient.getUserInventoryPermissions(inventoryId);

  Future<bool> removeInventoryMember(
          String memberId, String inventoryId) async =>
      await _supabaseClient.removeInventoryMember(memberId, inventoryId);

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
  }) async =>
      await _supabaseClient.updateInventoryMemberPermissions(
        memberId: memberId,
        inventoryId: inventoryId,
        role: role,
        canCreate: canCreate,
        canUpdate: canUpdate,
        canDelete: canDelete,
        canExport: canExport,
        canViewActivity: canViewActivity,
        canManageSettings: canManageSettings,
        canInviteMembers: canInviteMembers,
        canRemoveMembers: canRemoveMembers,
        canManageLabels: canManageLabels,
        canChat: canChat,
      );

  Future<bool> leaveInventory(String inventoryId) async =>
      await _supabaseClient.leaveInventory(inventoryId);

  Future<bool> deleteInventory(String inventoryId) async =>
      await _supabaseClient.deleteInventory(inventoryId);

  Future<bool> transferInventoryOwnership(
          String inventoryId, String newOwnerUserId) async =>
      await _supabaseClient.transferInventoryOwnership(
          inventoryId, newOwnerUserId);

  // ─── Invitation Operations ───────────────────────────────────
  Future<Map<String, dynamic>?> createInvitation({
    required String companyId,
    required String inventoryId,
    required String email,
    required String role,
  }) async =>
      await _supabaseClient.createInvitation(
        companyId: companyId,
        inventoryId: inventoryId,
        email: email,
        role: role,
      );

  Future<List<Map<String, dynamic>>> getPendingInvitations(
          String inventoryId) async =>
      await _supabaseClient.getPendingInvitations(inventoryId);

  Future<bool> cancelInvitation(String invitationId) async =>
      await _supabaseClient.cancelInvitation(invitationId);

  Future<Map<String, dynamic>?> acceptInvitation(String token) async =>
      await _supabaseClient.acceptInvitation(token);

  Future<void> autoJoinPendingInvitations() async {
    try {
      await _supabaseClient.autoJoinPendingInvitations();
    } catch (e) {
      debugPrint('⚠️ Auto-join failed: $e');
    }
  }

  // ─── Company Inventories ─────────────────────────────────────
  Future<List<Map<String, dynamic>>> getCompanyInventories(
          String companyId) async =>
      await _supabaseClient.getCompanyInventories(companyId);

  // ─── Activity Log ────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getInventoryActivity({
    required String inventoryId,
    DateTime? cursor,
    int limit = 50,
  }) async =>
      await _supabaseClient.getInventoryActivity(
        inventoryId: inventoryId,
        cursor: cursor,
        limit: limit,
      );

  Future<void> logActivity({
    required String inventoryId,
    required String action,
    required String entityType,
    required String entityName,
    String? labelName,
    String? details,
    Map<String, dynamic>? changes,
  }) async =>
      await _supabaseClient.logActivity(
        inventoryId: inventoryId,
        action: action,
        entityType: entityType,
        entityName: entityName,
        labelName: labelName,
        details: details,
        changes: changes,
      );

  // ─── Chat ────────────────────────────────────────────────────
  Future<void> markChatRoomRead(String roomId) async =>
      await _supabaseClient.markChatRoomRead(roomId);

  // ─── Profile ─────────────────────────────────────────────────
  Future<void> updateLastLogin() async =>
      await _supabaseClient.updateLastLogin();

  // ─── Notifications ───────────────────────────────────────────
  Future<bool> sendNotification({
    required String userId,
    required String title,
    required String message,
    String type = 'info',
  }) async =>
      await _supabaseClient.sendNotificationViaRpc(
        userId: userId,
        title: title,
        message: message,
        type: type,
      );

  // ─── Cache ───────────────────────────────────────────────────
  Future<void> _cacheCurrentUser() async {
    if (_currentUser == null) return;
    try {
      final authBox = await Hive.openBox('auth');
      await authBox.put('current_user', _currentUser!.toLocalJson());
      await authBox.put('email_confirmed', _emailConfirmed);
    } catch (e) {
      debugPrint('Cache error: $e');
    }
  }

  Future<void> _clearCache() async {
    try {
      final authBox = await Hive.openBox('auth');
      await authBox.delete('current_user');
      await authBox.delete('email_confirmed');
    } catch (e) {
      debugPrint('Clear cache error: $e');
    }
  }
}