import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/admin_service.dart';

part 'admin_event.dart';
part 'admin_state.dart';

class AdminBloc extends Bloc<AdminEvent, AdminState> {
  final AdminService _adminService;

  AdminBloc({required AdminService adminService})
      : _adminService = adminService,
        super(const AdminState()) {
    on<LoadAdminData>(_onLoadAdminData);
    on<LoadUsers>(_onLoadUsers);
    on<LoadAdminCompanies>(_onLoadCompanies);
    on<LoadAuditLogs>(_onLoadAuditLogs);
    on<LoadNotifications>(_onLoadNotifications);
    on<ApproveUser>(_onApproveUser);
    on<ForceConfirmUser>(_onForceConfirmUser);
    on<DeactivateUser>(_onDeactivateUser);
    on<CreateAdminUser>(_onCreateUser);
    on<UpdateUserRole>(_onUpdateUserRole);
    on<SendNotificationToUser>(_onSendNotification);
    on<MarkNotificationRead>(_onMarkNotificationRead);
    on<ClearAdminMessages>(_onClearMessages);
  }

  Future<void> _onLoadAdminData(
      LoadAdminData event, Emitter<AdminState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final isAdmin = await _adminService.isAdmin();
      final stats = isAdmin
          ? await _adminService.getStatistics()
          : <String, dynamic>{};
      emit(state.copyWith(
          isAdmin: isAdmin, statistics: stats, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoadUsers(
      LoadUsers event, Emitter<AdminState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final users = await _adminService.getAllUsers();
      emit(state.copyWith(users: users, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoadCompanies(
      LoadAdminCompanies event, Emitter<AdminState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final companies = await _adminService.getAllCompanies();
      emit(state.copyWith(companies: companies, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoadAuditLogs(
      LoadAuditLogs event, Emitter<AdminState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final logs = await _adminService.getAuditLogs();
      emit(state.copyWith(auditLogs: logs, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoadNotifications(
      LoadNotifications event, Emitter<AdminState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final notifications =
          await _adminService.getNotifications();
      emit(state.copyWith(
          notifications: notifications, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onApproveUser(
      ApproveUser event, Emitter<AdminState> emit) async {
    try {
      final success =
          await _adminService.approveUser(event.userId);
      emit(state.copyWith(
        successMessage:
            success ? 'User approved' : 'Failed to approve user',
      ));
      if (success) add(const LoadUsers());
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onForceConfirmUser(
      ForceConfirmUser event, Emitter<AdminState> emit) async {
    try {
      final success =
          await _adminService.forceConfirmUser(event.userId);
      emit(state.copyWith(
        successMessage: success
            ? 'User confirmed and approved'
            : 'Failed to confirm user',
      ));
      if (success) add(const LoadUsers());
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onDeactivateUser(
      DeactivateUser event, Emitter<AdminState> emit) async {
    try {
      final success =
          await _adminService.deactivateUser(event.userId);
      emit(state.copyWith(
        successMessage: success
            ? '${event.email} deactivated'
            : 'Failed to deactivate user',
      ));
      if (success) add(const LoadUsers());
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onCreateUser(
      CreateAdminUser event, Emitter<AdminState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final result = await _adminService.createUser(
        event.email,
        event.password,
        event.displayName,
        event.role,
      );
      final success = result['success'] == true;
      emit(state.copyWith(
        isLoading: false,
        successMessage: result['message']?.toString() ??
            (success ? 'User created' : 'Failed'),
      ));
      if (success) {
        add(const LoadUsers());
        add(const LoadAdminData());
      }
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onUpdateUserRole(
      UpdateUserRole event, Emitter<AdminState> emit) async {
    try {
      final success = await _adminService.updateUserRole(
          event.userId, event.newRole);
      emit(state.copyWith(
        successMessage: success
            ? 'Role updated to ${event.newRole}'
            : 'Failed to update role',
      ));
      if (success) add(const LoadUsers());
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onSendNotification(
      SendNotificationToUser event,
      Emitter<AdminState> emit) async {
    try {
      final success = await _adminService.sendNotification(
        event.userId,
        event.title,
        event.message,
      );
      emit(state.copyWith(
        successMessage: success
            ? 'Notification sent'
            : 'Failed to send notification',
      ));
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onMarkNotificationRead(
      MarkNotificationRead event,
      Emitter<AdminState> emit) async {
    try {
      await _adminService
          .markNotificationRead(event.notificationId);
      add(const LoadNotifications());
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  void _onClearMessages(
      ClearAdminMessages event, Emitter<AdminState> emit) {
    emit(state.copyWith(
      error: null,
      successMessage: null,
    ));
  }
}