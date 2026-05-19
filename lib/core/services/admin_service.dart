import 'package:supabase_flutter/supabase_flutter.dart';

class AdminService {
  final SupabaseClient _client = Supabase.instance.client;

  // Check if current user is admin
  Future<bool> isAdmin() async {
    try {
      final result = await _client.rpc('is_admin');
      return result as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  // Get dashboard statistics
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final result = await _client.rpc('get_admin_statistics');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  // Get all users
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final data = await _client
          .from('profiles')
          .select('*, auth_users:auth.users(email, email_confirmed_at, last_sign_in_at)')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      // Fallback without auth join
      try {
        final data = await _client
            .from('profiles')
            .select()
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(data);
      } catch (e2) {
        return [];
      }
    }
  }

  // Get all companies
  Future<List<Map<String, dynamic>>> getAllCompanies() async {
    try {
      final data = await _client
          .from('companies')
          .select('*, owner:profiles!owner_user_id(email, display_name)')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      return [];
    }
  }

  // Get audit logs
  Future<List<Map<String, dynamic>>> getAuditLogs({int limit = 50}) async {
    try {
      final data = await _client
          .from('admin_audit_log')
          .select('*, admin:admin_users(email)')
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      return [];
    }
  }

  // Approve user
  Future<bool> approveUser(String userId) async {
    try {
      final result = await _client.rpc('admin_approve_user', params: {'p_user_id': userId});
      return result['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // Deactivate user
  Future<bool> deleteUser(String userId) async {
    try {
      final result = await _client.rpc('admin_delete_user', params: {'p_user_id': userId});
      return result['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // Send notification
  Future<bool> sendNotification(String userId, String title, String message, {String type = 'info'}) async {
    try {
      final result = await _client.rpc('admin_send_notification', params: {
        'p_user_id': userId,
        'p_title': title,
        'p_message': message,
        'p_type': type,
      });
      return result['success'] == true;
    } catch (e) {
      return false;
    }
  }

  // Get notifications for current user
  Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final data = await _client
          .from('notifications')
          .select()
          .eq('user_id', _client.auth.currentUser?.id ?? '')
          .order('created_at', ascending: false)
          .limit(20);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      return [];
    }
  }

  // Mark notification as read
  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (_) {}
  }
}