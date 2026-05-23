part of 'admin_bloc.dart';

class AdminState {
  final bool isAdmin;
  final Map<String, dynamic> statistics;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> companies;
  final List<Map<String, dynamic>> auditLogs;
  final List<Map<String, dynamic>> notifications;
  final bool isLoading;
  final String? error;
  final String? successMessage;

  const AdminState({
    this.isAdmin = false,
    this.statistics = const {},
    this.users = const [],
    this.companies = const [],
    this.auditLogs = const [],
    this.notifications = const [],
    this.isLoading = false,
    this.error,
    this.successMessage,
  });

  AdminState copyWith({
    bool? isAdmin,
    Map<String, dynamic>? statistics,
    List<Map<String, dynamic>>? users,
    List<Map<String, dynamic>>? companies,
    List<Map<String, dynamic>>? auditLogs,
    List<Map<String, dynamic>>? notifications,
    bool? isLoading,
    String? error,
    String? successMessage,
  }) {
    return AdminState(
      isAdmin: isAdmin ?? this.isAdmin,
      statistics: statistics ?? this.statistics,
      users: users ?? this.users,
      companies: companies ?? this.companies,
      auditLogs: auditLogs ?? this.auditLogs,
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
    );
  }
}