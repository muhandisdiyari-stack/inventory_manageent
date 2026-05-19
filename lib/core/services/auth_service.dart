// ignore_for_file: unused_field

import 'package:hive_flutter/hive_flutter.dart';
import '../database/supabase/supabase_client.dart';
import '../models/user.dart';
import '../config/app_config.dart';

class AuthService {
  final SupabaseClientService _supabaseClient;

  User? _currentUser;
  bool _isAuthenticated = false;

  AuthService({
    required SupabaseClientService supabaseClient,
  }) : _supabaseClient = supabaseClient;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get requiresAuth => AppConfig.requiresAuth;

  Future<void> initialize() async {
    if (!requiresAuth) {
      _currentUser = User(
        id: 'local_user',
        email: 'local@inventory.pro',
        displayName: 'Local User',
        role: UserRole.owner,
        isApproved: true,
        createdAt: DateTime.now(),
      );
      _isAuthenticated = true;
      return;
    }

    try {
      final authBox = await Hive.openBox('auth');
      final cachedData = authBox.get('current_user');
      if (cachedData is Map) {
        _currentUser = User.fromLocalJson(Map<String, dynamic>.from(cachedData));
        _isAuthenticated = true;
      }
    } catch (_) {}
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
      await _cacheCurrentUser();
      return true;
    }

    try {
      final userData = await _supabaseClient.signIn(email, password);
      if (userData != null) {
        _currentUser = User.fromCloudJson(userData);
        _isAuthenticated = true;
        await _cacheCurrentUser();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> register(String email, String password, String displayName) async {
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
      await _cacheCurrentUser();
      return true;
    }

    try {
      final userData = await _supabaseClient.signUp(email, password, displayName);
      if (userData != null) {
        _currentUser = User.fromCloudJson(userData);
        _isAuthenticated = true;
        await _cacheCurrentUser();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> signOut() async {
    _currentUser = null;
    _isAuthenticated = false;
    await _supabaseClient.signOut();
    try {
      final authBox = await Hive.openBox('auth');
      await authBox.delete('current_user');
    } catch (_) {}
  }

  bool hasPermission(String permission) {
    return _currentUser?.hasPermission(permission) ?? false;
  }

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

  Future<List<Map<String, dynamic>>> getPendingInvitations(String companyId) async {
    return await _supabaseClient.getPendingInvitations(companyId);
  }

  Future<bool> cancelInvitation(String invitationId) async {
    return await _supabaseClient.cancelInvitation(invitationId);
  }

  Future<Map<String, dynamic>?> acceptInvitation(String token) async {
    return await _supabaseClient.acceptInvitation(token);
  }

  Future<List<Map<String, dynamic>>> getCompanyMembers(String companyId) async {
    return await _supabaseClient.getCompanyMembers(companyId);
  }

  Future<bool> removeMember(String memberId, String companyId) async {
    return await _supabaseClient.removeMember(memberId, companyId);
  }

  Future<bool> updateMemberRole(String memberId, String companyId, String newRole) async {
    return await _supabaseClient.updateMemberRole(memberId, companyId, newRole);
  }

  Future<bool> leaveCompany(String companyId) async {
    return await _supabaseClient.leaveCompany(companyId);
  }

  Future<void> _cacheCurrentUser() async {
    if (_currentUser == null) return;
    try {
      final authBox = await Hive.openBox('auth');
      await authBox.put('current_user', _currentUser!.toLocalJson());
    } catch (_) {}
  }
}