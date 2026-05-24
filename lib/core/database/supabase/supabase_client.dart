import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';

/// Returns the correct redirect URL for email confirmation based on platform.
///
/// - Web:             uses the browser's current origin  → "https://yourapp.com/auth/callback"
/// - Android/iOS:     custom URI scheme                  → "inventory://auth/callback"
/// - Windows/macOS/Linux: custom URI scheme              → "inventory://auth/callback"
///
/// This value must be added to Supabase Dashboard → Authentication → URL Configuration
/// → Redirect URLs.  The Site URL should be set to your web domain (or
/// http://localhost:3000 for local dev).
String _getEmailRedirectTo() {
  if (kIsWeb) {
    final origin = Uri.base.origin;
    final path = Uri.base.path; // e.g. "/inventory_manageent/"

    // GitHub Pages (or any subdirectory host): preserve the base path
    // so the redirect lands back inside the app, not at the domain root.
    // Flutter web hash routing means we append /#/auth/callback.
    if (path.length > 1) {
      // Hosted in a subdirectory e.g. /inventory_manageent/
      return '$origin$path#/auth/callback';
    }
    // Hosted at root e.g. https://yourdomain.com/
    return '$origin/#/auth/callback';
  }
  // Android, iOS, Windows, macOS, Linux
  return 'inventory://auth/callback';
}

class SupabaseClientService {
  late final SupabaseClient _client;
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
      debugPrint('❌ Supabase initialization failed: $e');
      if (AppConfig.isProduction) {
        throw Exception('Failed to initialize Supabase in production: $e');
      }
    }
  }

  SupabaseClient get client {
    if (!_isInitialized) {
      throw SupabaseNotInitializedException(
          _lastError ?? 'Supabase not initialized');
    }
    return _client;
  }

  /// Safe client access — returns null if not initialized instead of throwing.
  SupabaseClient? get safeClient => _isInitialized ? _client : null;

  // ─── Auth ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getCurrentUser() async {
    if (!isConfigured) return null;
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;
      try {
        await _client.auth.refreshSession();
      } catch (_) {
        return null; // Session expired
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
      final response = await _client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 10));

      final user = response.user;
      if (user == null) return null;

      // Retry with exponential backoff — profile row may not exist yet if the
      // database trigger is slow.
      Map<String, dynamic>? profileData;
      int retries = 0;
      const maxRetries = 3;

      while (retries < maxRetries) {
        try {
          profileData = await _client
              .from('profiles')
              .select()
              .eq('id', user.id)
              .maybeSingle();

          if (profileData != null) break;

          retries++;
          if (retries < maxRetries) {
            await Future.delayed(
                Duration(milliseconds: 300 * (retries + 1)));
          }
        } catch (e) {
          retries++;
          if (retries >= maxRetries) rethrow;
        }
      }

      if (profileData == null) {
        throw Exception('Profile not found after $maxRetries retries');
      }

      return {
        'id': user.id,
        'email': user.email,
        'display_name':
            profileData['display_name'] ?? user.userMetadata?['display_name'],
        'role': profileData['role'] ?? 'staff',
        'company_id': profileData['company_id'],
        'is_approved': profileData['is_approved'] ?? false,
        'email_confirmed': user.emailConfirmedAt != null,
        'created_at': user.createdAt,
        'permissions': profileData['permissions'] ?? {},
      };
    } on AuthException catch (e) {
      debugPrint('Auth error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Sign in error: $e');
      return null;
    }
  }

  /// ✅ FIX: Pass [emailRedirectTo] so Supabase embeds the correct callback
  /// URL inside the confirmation email.  Without this, Supabase has nowhere
  /// valid to redirect after the user clicks the link — causing the
  /// "requested path is invalid" error.
  Future<Map<String, dynamic>?> signUp(
      String email, String password, String displayName) async {
    if (!isConfigured) return null;
    try {
      final redirectUrl = _getEmailRedirectTo();
      debugPrint('📧 signUp emailRedirectTo: $redirectUrl');

      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
        // ✅ THE FIX: tells Supabase where to redirect after email confirmation.
        emailRedirectTo: redirectUrl,
      );

      final user = response.user;
      if (user == null) return null;

      // response.session == null  →  email confirmation is required (expected).
      // response.session != null  →  email confirmation is disabled in Supabase
      //                              dashboard; user is signed in immediately.
      final requiresConfirmation = response.session == null;

      return {
        'id': user.id,
        'email': user.email,
        'display_name': displayName,
        'created_at': user.createdAt,
        // true  = user must confirm before we create a session
        // false = no confirmation needed, proceed to app
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
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
  }

  /// Verifies the current session is valid by attempting a refresh.
  Future<bool> verifySession() async {
    if (!isConfigured) return false;
    try {
      await _client.auth.refreshSession();
      return _client.auth.currentSession != null;
    } catch (e) {
      return false;
    }
  }

  // ─── Company ──────────────────────────────────────────────────

  Future<Map<String, dynamic>?> createCompany(String name) async {
    if (!isConfigured) return null;
    try {
      final result = await _client
          .rpc('create_company', params: {'p_name': name.trim()});
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
      await _client.from('companies').update({
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
      final result = await _client.rpc('delete_company_cascade',
          params: {'p_company_id': companyId});
      return result is Map && result['success'] == true;
    } catch (e) {
      debugPrint('Delete company error: $e');
      try {
        await _client
            .from('inventory_items')
            .delete()
            .eq('company_id', companyId);
        await _client.from('labels').delete().eq('company_id', companyId);
        await _client
            .from('invitations')
            .delete()
            .eq('company_id', companyId);
        await _client
            .from('inventory_members')
            .delete()
            .eq('company_id', companyId);
        await _client
            .from('company_members')
            .delete()
            .eq('company_id', companyId);
        await _client.from('companies').delete().eq('id', companyId);
        return true;
      } catch (e2) {
        debugPrint('Fallback delete company error: $e2');
        return false;
      }
    }
  }

  Future<bool> leaveCompany(String companyId) async {
    if (!isConfigured) return false;
    try {
      final user = _client.auth.currentUser;
      if (user == null) return false;
      await _client
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
      final result = await _client.rpc('get_user_company');
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
      // Use the RPC function which handles all joins and RLS
      final data = await _client.rpc('get_user_companies');

      if (data is List) {
        return data.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return map;
        }).toList();
      }

      // Fallback: manual query if RPC fails
      final user = _client.auth.currentUser;
      if (user == null) return [];

      final memberships = await _client
          .from('company_members')
          .select('company_id, role, joined_at')
          .eq('user_id', user.id)
          .not('joined_at', 'is', null);

      if (memberships.isEmpty) return [];

      final companyIds = memberships
          .map((m) => m['company_id'] as String)
          .where((id) => id.isNotEmpty)
          .toList();

      if (companyIds.isEmpty) return [];

      final companiesData = await _client
          .from('companies')
          .select()
          .inFilter('id', companyIds);

      final membershipMap = <String, Map<String, dynamic>>{};
      for (final m in memberships) {
        membershipMap[m['company_id'] as String] = m;
      }

      return companiesData
          .map((c) => {
                'id': c['id'],
                'name': c['name'],
                'role': membershipMap[c['id']]?['role'] ?? 'staff',
                'joined_at': membershipMap[c['id']]?['joined_at'],
              })
          .toList();
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
      final data = await _client.rpc('get_company_members',
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
      final result = await _client.rpc('remove_member',
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
      final result = await _client.rpc('update_member_role', params: {
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
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final result = await _client.rpc('create_invitation', params: {
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
      final data = await _client
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
      await _client.from('invitations').update({
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
      final result = await _client
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
      var query = _client.from(table).select();
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
      await _client.from(table).insert(data);
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
      await _client.from(table).update(data).eq('id', id);
      return true;
    } catch (e) {
      debugPrint('Update error: $e');
      return false;
    }
  }

  Future<bool> softDelete(String table, String id) async {
    if (!isConfigured) return false;
    try {
      await _client.from(table).update({
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