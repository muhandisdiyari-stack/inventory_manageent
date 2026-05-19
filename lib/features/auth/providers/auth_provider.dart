import 'package:flutter/foundation.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/models/user.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;

  AuthProvider({required AuthService authService}) : _authService = authService;

  // ─── Getters ────────────────────────────────────────────────────

  User? get currentUser => _authService.currentUser;
  bool get isAuthenticated => _authService.isAuthenticated;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get requiresAuth => _authService.requiresAuth;
  String? get error => _error;

  // ─── Permissions ────────────────────────────────────────────────

  bool hasPermission(String permission) => _authService.hasPermission(permission);

  bool get canManageCompany => hasPermission('manage_company');
  bool get canManageUsers => hasPermission('manage_users');
  bool get canManageInventory => hasPermission('manage_inventory');
  bool get canViewInventory => hasPermission('view_inventory');
  bool get canExportReports => hasPermission('export_reports');
  bool get canBulkImport => hasPermission('bulk_import');
  bool get canDeleteItems => hasPermission('delete_items');

  // ─── Initialization ─────────────────────────────────────────────

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _authService.initialize();
      _isInitialized = true;
    } catch (e) {
      _error = 'Failed to initialize auth: $e';
      debugPrint('AuthProvider initialization error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Authentication Actions ─────────────────────────────────────

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _authService.signIn(email.trim(), password);
      if (success) {
        _error = null;
      } else {
        _error = 'Invalid email or password';
      }
      return success;
    } catch (e) {
      _error = e.toString();
      debugPrint('Sign in error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register(String email, String password, String displayName) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _authService.register(
        email.trim(), 
        password, 
        displayName.trim(),
      );
      if (!success) {
        _error = 'Registration failed. Please try again.';
      }
      return success;
    } catch (e) {
      _error = e.toString();
      debugPrint('Registration error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.signOut();
      _error = null;
    } catch (e) {
      _error = 'Sign out error: $e';
      debugPrint('Sign out error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh the current user's session
  Future<bool> refreshSession() async {
    try {
      await _authService.initialize();
      notifyListeners();
      return isAuthenticated;
    } catch (e) {
      debugPrint('Session refresh error: $e');
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}