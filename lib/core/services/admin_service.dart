import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminService {
  final SupabaseClient? _client;
  AdminService({SupabaseClient? client}) : _client = client;

  SupabaseClient get _safeClient {
    final client = _client;
    if (client != null) return client;
    return Supabase.instance.client;
  }

  Future<bool> isAdmin() async {
    try {
      final currentUser = _safeClient.auth.currentUser;
      if (currentUser == null) return false;
      final result = await _safeClient.rpc('is_admin',
          params: {'p_user_id': currentUser.id});
      return result == true;
    } catch (e) {
      debugPrint('isAdmin check failed: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final result = await _safeClient.rpc('get_admin_statistics');
      if (result is Map) return Map<String, dynamic>.from(result);
      return {};
    } catch (e) {
      debugPrint('AdminService.getStatistics error: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getAllUsers({int offset = 0, int limit = 50}) async {
    try {
      final data = await _safeClient.rpc('get_admin_users_list', params: {
        'p_offset': offset,
        'p_limit': limit,
      });
      if (data is List) return List<Map<String, dynamic>>.from(data);
      return [];
    } catch (e) {
      debugPrint('AdminService.getAllUsers error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getUserDetails(String userId) async {
    try {
      final result = await _safeClient.rpc('admin_get_user_details',
          params: {'p_user_id': userId});
      if (result is Map) return Map<String, dynamic>.from(result);
      return {};
    } catch (e) {
      debugPrint('AdminService.getUserDetails error: $e');
      return {};
    }
  }

  Future<bool> approveUser(String userId) async {
    try {
      final result = await _safeClient.rpc('admin_approve_user',
          params: {'p_user_id': userId});
      return result is Map && result['success'] == true;
    } catch (e) {
      debugPrint('AdminService.approveUser error: $e');
      return false;
    }
  }

  Future<bool> forceConfirmUser(String userId) async {
    try {
      final result = await _safeClient.rpc('admin_force_confirm_user',
          params: {'p_user_id': userId});
      return result is Map && result['success'] == true;
    } catch (e) {
      debugPrint('AdminService.forceConfirmUser error: $e');
      return false;
    }
  }

  Future<bool> deactivateUser(String userId) async {
    try {
      final result = await _safeClient.rpc('admin_deactivate_user',
          params: {'p_user_id': userId});
      return result is Map && result['success'] == true;
    } catch (e) {
      debugPrint('AdminService.deactivateUser error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> createUser(
    String email,
    String password,
    String displayName,
    String role,
  ) async {
    try {
      final result = await _safeClient.rpc('admin_create_user', params: {
        'p_email': email,
        'p_password': password,
        'p_display_name': displayName,
        'p_role': role,
      });
      if (result is Map) return Map<String, dynamic>.from(result);
      return {'success': false, 'message': 'Failed to create user'};
    } catch (e) {
      debugPrint('AdminService.createUser error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> updateUserRole(String userId, String newRole) async {
    try {
      final result = await _safeClient.rpc('admin_update_user_role', params: {
        'p_user_id': userId,
        'p_new_role': newRole,
      });
      return result is Map && result['success'] == true;
    } catch (e) {
      debugPrint('AdminService.updateUserRole error: $e');
      return false;
    }
  }

  /// The DB returns `full_name`, we map to `owner_name` for UI compatibility.
  Future<List<Map<String, dynamic>>> getAllCompanies({int offset = 0, int limit = 50}) async {
    try {
      final data = await _safeClient.rpc('get_admin_companies_list', params: {
        'p_offset': offset,
        'p_limit': limit,
      });
      if (data is List) {
        return data.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          if (map.containsKey('full_name') && !map.containsKey('owner_name')) {
            map['owner_name'] = map['full_name'];
          }
          return map;
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint('AdminService.getAllCompanies error: $e');
      return [];
    }
  }

  Future<bool> sendNotification(
    String userId,
    String title,
    String message, {
    String type = 'info',
  }) async {
    try {
      await _safeClient.rpc('send_notification', params: {
        'p_user_id': userId,
        'p_title': title,
        'p_message': message,
        'p_type': type,
      });
      return true;
    } catch (e) {
      debugPrint('AdminService.sendNotification error: $e');
      return false;
    }
  }

  Future<bool> sendEmail(String userId, String subject, String body) async {
    try {
      final result = await _safeClient.rpc('admin_send_email', params: {
        'p_user_id': userId,
        'p_subject': subject,
        'p_body': body,
      });
      return result is Map && result['success'] == true;
    } catch (e) {
      debugPrint('AdminService.sendEmail error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final userId = _safeClient.auth.currentUser?.id;
      if (userId == null) return [];
      final data = await _safeClient
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(20);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('AdminService.getNotifications error: $e');
      return [];
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _safeClient
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (e) {
      debugPrint('AdminService.markNotificationRead error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAuditLogs({int limit = 50}) async {
    try {
      final data = await _safeClient
          .from('admin_audit_log')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('AdminService.getAuditLogs error: $e');
      return [];
    }
  }
}