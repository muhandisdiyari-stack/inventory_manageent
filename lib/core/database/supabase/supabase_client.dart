import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';

/// Returns the correct redirect URL for email confirmation based on platform.
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

/// Centralized Supabase client service.
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

  /// Returns the Supabase client. Throws if not initialized.
  SupabaseClient get client {
    if (!_isInitialized || _client == null) {
      throw SupabaseNotInitializedException(
          _lastError ?? 'Supabase not initialized');
    }
    return _client!;
  }

  /// Safe client access — returns null if not initialized.
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

// In the signIn method, change the catch block:

  Future<Map<String, dynamic>?> signIn(String email, String password) async {
    if (!isConfigured) return null;
    try {
      final response = await _client!.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 15));

      final user = response.user;
      if (user == null) return null;

      // Get profile data
      Map<String, dynamic>? profileData;
      try {
        profileData = await _client!
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        debugPrint('🔍 Profile data: $profileData');
      } catch (e) {
        debugPrint('⚠️ Profile fetch error: $e');
      }

      return {
        'id': user.id,
        'email': user.email,
        'display_name':
            profileData?['display_name'] ?? user.userMetadata?['display_name'],
        'role': profileData?['role'] ?? 'viewer',
        'company_id': profileData?['company_id'],
        'is_approved': profileData?['is_approved'] ?? true, // Default true after our migration
        'email_confirmed': user.emailConfirmedAt != null,
        'created_at': user.createdAt,
        'permissions': profileData?['permissions'] ?? {},
      };
    } on AuthException {
      // ✅ Re-throw so AuthBloc can show the proper message
      rethrow;
    } catch (e) {
      debugPrint('Sign in error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> signUp(
      String email, String password, String displayName) async {
    if (!isConfigured) return null;
    try {
      final redirectUrl = _getEmailRedirectTo();
      debugPrint('📧 signUp emailRedirectTo: $redirectUrl');

      final response = await _client!.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
        emailRedirectTo: redirectUrl,
      );

      final user = response.user;
      if (user == null) return null;

      final requiresConfirmation = response.session == null;

      return {
        'id': user.id,
        'email': user.email,
        'display_name': displayName,
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

  /// Verifies the current session is valid.
  /// Returns false only if definitively signed out, true otherwise.
  Future<bool> verifySession() async {
    if (!isConfigured) return false;

    try {
      // Check if there's an existing session without refreshing
      final currentSession = _client!.auth.currentSession;
      if (currentSession == null) {
        debugPrint('🔍 verifySession: No current session');
        return false;
      }

      // Check if session is still valid (not expired)
      final expiresAt = currentSession.expiresAt;
      final nowInSeconds =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

      if (expiresAt != null && expiresAt > nowInSeconds) {
        // Session still valid, no need to refresh
        debugPrint('🔍 verifySession: Session valid until ${DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)}');
        return true;
      }

      // Session expired or about to expire, try to refresh
      debugPrint('🔍 verifySession: Session expired, attempting refresh...');
      try {
        await _client!.auth.refreshSession();
        final newSession = _client!.auth.currentSession;
        debugPrint('🔍 verifySession: Refresh ${newSession != null ? 'successful' : 'failed'}');
        return newSession != null;
      } catch (refreshError) {
        debugPrint('🔍 verifySession: Refresh error: $refreshError');
        // Check if there's still a current session despite refresh error
        return _client!.auth.currentSession != null;
      }
    } catch (e) {
      debugPrint('🔍 verifySession: Unexpected error: $e');
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

  Future<bool> updateCompany(String companyId, String newName) async {
    if (!isConfigured) return false;
    try {
      await _client!.from('companies').update({
        'name': newName.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', companyId);
      return true;
    } catch (e) {
      debugPrint('Update company error: $e');
      return false;
    }
  }

  Future<bool> deleteCompany(String companyId) async {
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

  Future<bool> leaveCompany(String companyId) async {
    if (!isConfigured) return false;
    try {
      final user = _client!.auth.currentUser;
      if (user == null) return false;
      await _client!
          .from('company_members')
          .delete()
          .eq('user_id', user.id)
          .eq('company_id', companyId);
      return true;
    } catch (e) {
      debugPrint('Leave company error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getUserCompany() async {
    if (!isConfigured) return null;
    try {
      final result = await _client!.rpc('get_user_company');
      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        if (map['has_company'] == true) return map;
      }
      return null;
    } catch (e) {
      debugPrint('Get user company error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getUserCompanies() async {
    if (!isConfigured) return [];
    try {
      final data = await _client!.rpc('get_user_companies');
      if (data is List) {
        return data
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Get user companies error: $e');
      return [];
    }
  }

  // ─── Members ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCompanyMembers(
      String companyId) async {
    if (!isConfigured) return [];
    try {
      final data = await _client!.rpc('get_company_members',
          params: {'p_company_id': companyId});
      if (data is List) return List<Map<String, dynamic>>.from(data);
      return [];
    } catch (e) {
      debugPrint('Get members error: $e');
      return [];
    }
  }

  Future<bool> removeMember(String memberId, String companyId) async {
    if (!isConfigured) return false;
    try {
      final result = await _client!.rpc('remove_member',
          params: {'p_member_id': memberId, 'p_company_id': companyId});
      if (result is Map) return result['success'] == true;
      return false;
    } catch (e) {
      debugPrint('Remove member error: $e');
      return false;
    }
  }

  Future<bool> updateMemberRole(
      String memberId, String companyId, String newRole) async {
    if (!isConfigured) return false;
    try {
      final result = await _client!.rpc('update_member_role', params: {
        'p_member_id': memberId,
        'p_company_id': companyId,
        'p_new_role': newRole,
      });
      if (result is Map) return result['success'] == true;
      return false;
    } catch (e) {
      debugPrint('Update role error: $e');
      return false;
    }
  }

  // ─── Invitations ──────────────────────────────────────────────

  Future<Map<String, dynamic>?> createInvitation({
    required String companyId,
    required String email,
    required String role,
  }) async {
    if (!isConfigured) return null;
    try {
      final user = _client!.auth.currentUser;
      if (user == null) return null;

      final result = await _client!.rpc('create_invitation', params: {
        'p_company_id': companyId,
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
      String companyId) async {
    if (!isConfigured) return [];
    try {
      final data = await _client!
          .from('invitations')
          .select()
          .eq('company_id', companyId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Get invitations error: $e');
      return [];
    }
  }

  Future<bool> cancelInvitation(String invitationId) async {
    if (!isConfigured) return false;
    try {
      await _client!.from('invitations').update({
        'status': 'cancelled',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', invitationId);
      return true;
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