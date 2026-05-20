// ignore_for_file: unused_field

import 'package:hive_flutter/hive_flutter.dart';
import '../database/supabase/supabase_client.dart';
import '../models/user.dart';
import '../config/app_config.dart';

/// Result class for registration operations.
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

  AuthService({required SupabaseClientService supabaseClient})
      : _supabaseClient = supabaseClient;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isEmailConfirmed => _emailConfirmed;
  bool get requiresAuth => AppConfig.requiresAuth;

  // ─── Initialize ───────────────────────────────────────────────

  Future<void> initialize() async {
    // Development offline mode — skip auth entirely.
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

        // Verify the Supabase session is still valid.
        try {
          final isValid = await _supabaseClient.verifySession();
          if (!isValid) {
            await _clearCache();
            _isAuthenticated = false;
          } else {
            _isAuthenticated = true;
          }
        } catch (_) {
          // Offline — trust cached session.
          _isAuthenticated = true;
        }
      }
    } catch (_) {
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
    // Offline / no-auth mode.
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
        _emailConfirmed = userData['email_confirmed'] as bool? ?? true;
        await _cacheCurrentUser();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ─── Register ─────────────────────────────────────────────────

  /// ✅ FIX: The [signUp] call in [SupabaseClientService] now passes
  /// [emailRedirectTo], so the confirmation email contains a valid deep-link
  /// back into the app.  The logic here correctly reads the
  /// `email_confirmed` flag returned by [signUp]:
  ///
  ///   email_confirmed == false  →  user must click the confirmation link
  ///                                before they can use the app.
  ///   email_confirmed == true   →  Supabase email confirmation is disabled;
  ///                                log the user in immediately.
  Future<RegistrationResult> register(
      String email, String password, String displayName) async {
    // Offline / no-auth mode.
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
          success: true, requiresEmailConfirmation: false);
    }

    try {
      final userData =
          await _supabaseClient.signUp(email, password, displayName);

      if (userData == null) {
        return RegistrationResult(
            success: false, error: 'Registration failed. Please try again.');
      }

      // ✅ FIX: supabase_client.dart now sets email_confirmed = !requiresConfirmation,
      // so we read it directly — no inverted boolean bug.
      final emailConfirmed = userData['email_confirmed'] as bool? ?? false;

      if (!emailConfirmed) {
        // Email confirmation is required.
        // Do NOT create a session — user must click the link first.
        return RegistrationResult(
          success: true,
          requiresEmailConfirmation: true,
          email: email,
        );
      } else {
        // Email confirmation is disabled in Supabase dashboard.
        // Authenticate the user immediately.
        _currentUser = User.fromCloudJson(userData);
        _isAuthenticated = true;
        _emailConfirmed = true;
        await _cacheCurrentUser();
        return RegistrationResult(
            success: true, requiresEmailConfirmation: false);
      }
    } catch (e) {
      return RegistrationResult(success: false, error: e.toString());
    }
  }

  // ─── Sign Out ─────────────────────────────────────────────────

  Future<void> signOut() async {
    _currentUser = null;
    _isAuthenticated = false;
    _emailConfirmed = false;
    await _supabaseClient.signOut();
    await _clearCache();
  }

  // ─── Permissions ──────────────────────────────────────────────

  bool hasPermission(String permission) =>
      _currentUser?.hasPermission(permission) ?? false;

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