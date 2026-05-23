part of 'admin_bloc.dart';

sealed class AdminEvent {
  const AdminEvent();
}

class LoadAdminData extends AdminEvent {
  const LoadAdminData();
}

class LoadUsers extends AdminEvent {
  const LoadUsers();
}

class LoadAdminCompanies extends AdminEvent {
  const LoadAdminCompanies();
}

class LoadAuditLogs extends AdminEvent {
  const LoadAuditLogs();
}

class LoadNotifications extends AdminEvent {
  const LoadNotifications();
}

class ApproveUser extends AdminEvent {
  final String userId;
  const ApproveUser(this.userId);
}

class ForceConfirmUser extends AdminEvent {
  final String userId;
  const ForceConfirmUser(this.userId);
}

class DeactivateUser extends AdminEvent {
  final String userId;
  final String email;
  const DeactivateUser(this.userId, this.email);
}

class CreateAdminUser extends AdminEvent {
  final String email;
  final String password;
  final String displayName;
  final String role;
  const CreateAdminUser({
    required this.email,
    required this.password,
    required this.displayName,
    required this.role,
  });
}

class UpdateUserRole extends AdminEvent {
  final String userId;
  final String newRole;
  const UpdateUserRole(this.userId, this.newRole);
}

class SendNotificationToUser extends AdminEvent {
  final String userId;
  final String title;
  final String message;
  const SendNotificationToUser({
    required this.userId,
    required this.title,
    required this.message,
  });
}

class MarkNotificationRead extends AdminEvent {
  final String notificationId;
  const MarkNotificationRead(this.notificationId);
}

class ClearAdminMessages extends AdminEvent {
  const ClearAdminMessages();
}