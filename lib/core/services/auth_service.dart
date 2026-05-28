import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
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

  // ─── Setters for AuthBloc access ─────────────────────────────

  set currentUser(User? user) {
    _currentUser = user;
  }

  set isAuthenticatedValue(bool value) {
    _isAuthenticated = value;
  }

  // ─── Initialize ───────────────────────────────────────────────

  Future<void> initialize() async {
    debugPrint('🔍 AuthService.initialize() called');

    // Development offline mode — skip auth entirely
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
      debugPrint('🔍 AuthService: Development offline mode - authenticated');
      return;
    }

    if (!requiresAuth) {
      _isAuthenticated = false;
      debugPrint('🔍 AuthService: Auth not required');
      return;
    }

    try {
      final authBox = await Hive.openBox('auth');
      final cachedData = authBox.get('current_user');

      if (cachedData is Map) {
        _currentUser =
            User.fromLocalJson(Map<String, dynamic>.from(cachedData));
        _emailConfirmed =
            authBox.get('email_confirmed', defaultValue: false) as bool? ??
                false;
        debugPrint('🔍 AuthService: Found cached user: ${_currentUser?.email}');

        // Verify the Supabase session is still valid
        if (AppConfig.useSupabase) {
          try {
            final isValid = await _supabaseClient.verifySession();
            if (!isValid) {
              debugPrint('⚠️ AuthService: Session invalid, will show login');
              _isAuthenticated = false;
            } else {
              debugPrint('✅ AuthService: Session valid');
              _isAuthenticated = true;
            }
          } catch (e) {
            debugPrint('⚠️ AuthService: Session verification error: $e');
            _isAuthenticated = true;
          }
        } else {
          _isAuthenticated = true;
        }
      } else {
        debugPrint('🔍 AuthService: No cached user found');
        _isAuthenticated = false;
      }
    } catch (e) {
      debugPrint('❌ AuthService.initialize error: $e');
      _isAuthenticated = false;
    }
  }

  // ─── Company helpers ──────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getUserCompanies() async {
    try {
      return await _supabaseClient.getUserCompanies();
    } catch (_) {
      return [];
    }
  }

  // ─── Sign In ──────────────────────────────────────────────────

  Future<bool> signIn(String email, String password) async {
    debugPrint('🔍 AuthService.signIn: $email');

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
        await _cacheCurrentUser();
        debugPrint('✅ AuthService.signIn: Success - ${_currentUser?.email}');
        return true;
      }
      debugPrint('❌ AuthService.signIn: Failed - no user data');
      return false;
    } catch (e) {
      debugPrint('❌ AuthService.signIn: Exception - $e');
      return false;
    }
  }

  // ─── Register ─────────────────────────────────────────────────

  Future<RegistrationResult> register(
      String email, String password, String displayName) async {
    debugPrint('🔍 AuthService.register: $email');

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
            success: false, error: 'Registration failed. Please try again.');
      }

      final emailConfirmed = userData['email_confirmed'] as bool? ?? false;

      if (!emailConfirmed) {
        return RegistrationResult(
          success: true,
          requiresEmailConfirmation: true,
          email: email,
        );
      } else {
        _currentUser = User.fromCloudJson(userData);
        _isAuthenticated = true;
        _emailConfirmed = true;
        await _cacheCurrentUser();
        return const RegistrationResult(
            success: true, requiresEmailConfirmation: false);
      }
    } catch (e) {
      return RegistrationResult(success: false, error: e.toString());
    }
  }

  // ─── Sign Out ─────────────────────────────────────────────────

  Future<void> signOut() async {
    debugPrint('🔍 AuthService.signOut');
    _currentUser = null;
    _isAuthenticated = false;
    _emailConfirmed = false;
    await _supabaseClient.signOut();
    await _clearCache();
  }

  // ─── Permissions ──────────────────────────────────────────────

  bool hasPermission(String permission) {
    if (_currentUser == null) return false;
    switch (_currentUser!.role) {
      case UserRole.owner:
        return true;
      case UserRole.admin:
        return permission != 'manage_company';
      case UserRole.dataOperator:
        return [
          'view_inventory',
          'manage_inventory',
          'export_reports',
          'bulk_import'
        ].contains(permission);
      case UserRole.viewer:
        return ['view_inventory', 'export_reports'].contains(permission);
    }
  }

  // ─── Company operations ───────────────────────────────────────

  Future<Map<String, dynamic>?> createCompany(String name) async =>
      await _supabaseClient.createCompany(name);

  Future<bool> updateCompany(String companyId, String newName) async =>
      await _supabaseClient.updateCompany(companyId, newName);

  Future<bool> deleteCompany(String companyId) async =>
      await _supabaseClient.deleteCompany(companyId);

  Future<Map<String, dynamic>?> getUserCompany() async =>
      await _supabaseClient.getUserCompany();

  // ─── Invitation operations ────────────────────────────────────

  Future<Map<String, dynamic>?> createInvitation({
    required String companyId,
    required String email,
    required String role,
  }) async =>
      await _supabaseClient.createInvitation(
          companyId: companyId, email: email, role: role);

  Future<List<Map<String, dynamic>>> getPendingInvitations(
          String companyId) async =>
      await _supabaseClient.getPendingInvitations(companyId);

  Future<bool> cancelInvitation(String invitationId) async =>
      await _supabaseClient.cancelInvitation(invitationId);

  Future<Map<String, dynamic>?> acceptInvitation(String token) async =>
      await _supabaseClient.acceptInvitation(token);

  // ─── Member operations ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCompanyMembers(
          String companyId) async =>
      await _supabaseClient.getCompanyMembers(companyId);

  Future<bool> removeMember(String memberId, String companyId) async =>
      await _supabaseClient.removeMember(memberId, companyId);

  Future<bool> updateMemberRole(
          String memberId, String companyId, String newRole) async =>
      await _supabaseClient.updateMemberRole(memberId, companyId, newRole);

  Future<bool> leaveCompany(String companyId) async =>
      await _supabaseClient.leaveCompany(companyId);

  // ─── Cache ────────────────────────────────────────────────────

  Future<void> _cacheCurrentUser() async {
    if (_currentUser == null) return;
    try {
      final authBox = await Hive.openBox('auth');
      await authBox.put('current_user', _currentUser!.toLocalJson());
      await authBox.put('email_confirmed', _emailConfirmed);
      debugPrint('🔍 AuthService: Cached user saved');
    } catch (e) {
      debugPrint('AuthService cache error: $e');
    }
  }

  Future<void> _clearCache() async {
    try {
      final authBox = await Hive.openBox('auth');
      await authBox.delete('current_user');
      await authBox.delete('email_confirmed');
      debugPrint('🔍 AuthService: Cache cleared');
    } catch (e) {
      debugPrint('AuthService clear cache error: $e');
    }
  }
}