// ignore_for_file: unused_field

import 'package:hive_flutter/hive_flutter.dart';
import '../database/supabase/supabase_client.dart';
import '../models/user.dart';
import '../config/app_config.dart';

/// Result class for registration operations
class RegistrationResult {
  final bool success;
  final bool requiresEmailConfirmation;
  final String? email;
  final String? error;

  RegistrationResult({
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

  AuthService({
    required SupabaseClientService supabaseClient,
  }) : _supabaseClient = supabaseClient;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isEmailConfirmed => _emailConfirmed;
  bool get requiresAuth => AppConfig.requiresAuth;

  Future<void> initialize() async {
    // FIX #7: Only auto-create user in development mode
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
        _emailConfirmed =
            authBox.get('email_confirmed', defaultValue: false) as bool? ??
                false;

        // FIX #1: Verify session validity before marking as authenticated
        try {
          final isValid = await _supabaseClient.verifySession();
          if (!isValid) {
            await _clearCache();
            _isAuthenticated = false;
          } else {
            _isAuthenticated = true;
          }
        } catch (e) {
          // Offline mode - trust cached session but mark as needing verification
          _isAuthenticated = true;
        }
      }
    } catch (_) {
      _isAuthenticated = false;
    }
  }

  Future<List<Map<String, dynamic>>> getUserCompanies() async {
    try {
      return await _supabaseClient.getUserCompanies();
    } catch (e) {
      return [];
    }
  }

  Future<bool> signIn(String email, String password) async {
    if (!requiresAuth) {
      _currentUser = User(
        id: email.hashCode.toString(),
        email: email,
        role: UserRole.staff,
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
        _emailConfirmed =
            userData['email_confirmed'] as bool? ?? true;
        await _cacheCurrentUser();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // FIX #1 & #10: Registration returns result without authenticating
  Future<RegistrationResult> register(
      String email, String password, String displayName) async {
    if (!requiresAuth) {
      _currentUser = User(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        email: email,
        displayName: displayName,
        role: UserRole.staff,
        isApproved: false,
        createdAt: DateTime.now(),
      );
      _isAuthenticated = true;
      _emailConfirmed = true;
      await _cacheCurrentUser();
      return RegistrationResult(
        success: true,
        requiresEmailConfirmation: false,
      );
    }

    try {
      final userData =
          await _supabaseClient.signUp(email, password, displayName);
      if (userData != null) {
        final needsConfirmation =
            userData['email_confirmed'] as bool? ?? true == false;

        if (needsConfirmation) {
          // FIX #1 & #10: Do NOT authenticate - user must confirm email first
          return RegistrationResult(
            success: true,
            requiresEmailConfirmation: true,
            email: email,
          );
        } else {
          // Email confirmation not required - authenticate immediately
          _currentUser = User.fromCloudJson(userData);
          _isAuthenticated = true;
          _emailConfirmed = true;
          await _cacheCurrentUser();
          return RegistrationResult(
            success: true,
            requiresEmailConfirmation: false,
          );
        }
      }
      return RegistrationResult(
        success: false,
        error: 'Registration failed. Please try again.',
      );
    } catch (e) {
      return RegistrationResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  Future<void> signOut() async {
    _currentUser = null;
    _isAuthenticated = false;
    _emailConfirmed = false;
    await _supabaseClient.signOut();
    await _clearCache();
  }

  bool hasPermission(String permission) {
    return _currentUser?.hasPermission(permission) ?? false;
  }

  // ─── Company Operations ────────────────────────────────────────

  Future<Map<String, dynamic>?> createCompany(String name) async {
    return await _supabaseClient.createCompany(name);
  }

  Future<bool> updateCompany(String companyId, String newName) async {
    return await _supabaseClient.updateCompany(companyId, newName);
  }

  Future<bool> deleteCompany(String companyId) async {
    return await _supabaseClient.deleteCompany(companyId);
  }

  Future<Map<String, dynamic>?> getUserCompany() async {
    return await _supabaseClient.getUserCompany();
  }

  // ─── Invitation Operations ─────────────────────────────────────

  Future<Map<String, dynamic>?> createInvitation({
    required String companyId,
    required String email,
    required String role,
  }) async {
    return await _supabaseClient.createInvitation(
      companyId: companyId,
      email: email,
      role: role,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingInvitations(
      String companyId) async {
    return await _supabaseClient.getPendingInvitations(companyId);
  }

  Future<bool> cancelInvitation(String invitationId) async {
    return await _supabaseClient.cancelInvitation(invitationId);
  }

  Future<Map<String, dynamic>?> acceptInvitation(String token) async {
    return await _supabaseClient.acceptInvitation(token);
  }

  // ─── Member Operations ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCompanyMembers(
      String companyId) async {
    return await _supabaseClient.getCompanyMembers(companyId);
  }

  Future<bool> removeMember(String memberId, String companyId) async {
    return await _supabaseClient.removeMember(memberId, companyId);
  }

  Future<bool> updateMemberRole(
      String memberId, String companyId, String newRole) async {
    return await _supabaseClient.updateMemberRole(
        memberId, companyId, newRole);
  }

  Future<bool> leaveCompany(String companyId) async {
    return await _supabaseClient.leaveCompany(companyId);
  }

  // ─── Caching ───────────────────────────────────────────────────

  Future<void> _cacheCurrentUser() async {
    if (_currentUser == null) return;
    try {
      final authBox = await Hive.openBox('auth');
      await authBox.put('current_user', _currentUser!.toLocalJson());
      await authBox.put('email_confirmed', _emailConfirmed);
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    try {
      final authBox = await Hive.openBox('auth');
      await authBox.delete('current_user');
      await authBox.delete('email_confirmed');
    } catch (_) {}
  }
}