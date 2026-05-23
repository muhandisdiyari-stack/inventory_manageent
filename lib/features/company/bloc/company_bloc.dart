import 'package:flutter_bloc/flutter_bloc.dart';
// FIX 3: Removed unused import 'package:flutter/services.dart'.
import '../../../core/services/auth_service.dart';

part 'company_event.dart';
part 'company_state.dart';

class CompanyBloc extends Bloc<CompanyEvent, CompanyState> {
  final AuthService _authService;

  CompanyBloc({required AuthService authService})
      : _authService = authService,
        super(const CompanyState()) {
    on<LoadCompanies>(_onLoadCompanies);
    on<SelectCompany>(_onSelectCompany);
    on<CreateCompany>(_onCreateCompany);
    on<DeleteCompany>(_onDeleteCompany);
    on<LeaveCompany>(_onLeaveCompany);
    on<JoinCompany>(_onJoinCompany);
    on<CreateInvitation>(_onCreateInvitation);
    on<CancelInvitation>(_onCancelInvitation);
    on<RemoveMember>(_onRemoveMember);
    on<ChangeMemberRole>(_onChangeMemberRole);
    on<ClearMessages>(_onClearMessages);
  }

  /// Loads all companies for the current user.
  /// If companies exist, also loads members and invitations for the first company.
  Future<void> _onLoadCompanies(
      LoadCompanies event, Emitter<CompanyState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final companies = await _authService.getUserCompanies();

      if (companies.isEmpty) {
        emit(state.copyWith(
          companies: [],
          selectedCompany: null,
          members: [],
          invitations: [],
          isLoading: false,
        ));
        return;
      }

      // Keep the currently selected company if it still exists in the list,
      // otherwise default to the first company.
      final currentSelectedId = state.selectedCompany?['company']?['id']?.toString();
      Map<String, dynamic>? targetCompany;

      if (currentSelectedId != null) {
        targetCompany = companies.cast<Map<String, dynamic>?>().firstWhere(
              (c) => c?['id']?.toString() == currentSelectedId,
              orElse: () => companies.first,
            );
      } else {
        targetCompany = companies.first;
      }

      // Load members and invitations for the selected company
      List<Map<String, dynamic>> members = [];
      List<Map<String, dynamic>> invitations = [];

      if (targetCompany != null) {
        final companyId = targetCompany['id']?.toString();
        if (companyId != null && companyId.isNotEmpty) {
          try {
            members = await _authService.getCompanyMembers(companyId);
          } catch (e) {
            // Members load failed - continue with empty list
          }
          try {
            invitations =
                await _authService.getPendingInvitations(companyId);
          } catch (e) {
            // Invitations load failed - continue with empty list
          }
        }
      }

      emit(state.copyWith(
        companies: companies,
        selectedCompany: targetCompany,
        members: members,
        invitations: invitations,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, error: 'Failed to load companies: $e'));
    }
  }

  /// Selects a company and loads its members and invitations.
  Future<void> _onSelectCompany(
      SelectCompany event, Emitter<CompanyState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final targetCompany = state.companies.cast<Map<String, dynamic>?>().firstWhere(
            (c) => c?['id']?.toString() == event.companyId,
            orElse: () => null,
          );

      if (targetCompany == null) {
        emit(state.copyWith(
            isLoading: false,
            error: 'Company not found'));
        return;
      }

      // Load members and invitations for this company
      List<Map<String, dynamic>> members = [];
      List<Map<String, dynamic>> invitations = [];

      try {
        members = await _authService.getCompanyMembers(event.companyId);
      } catch (_) {}
      try {
        invitations =
            await _authService.getPendingInvitations(event.companyId);
      } catch (_) {}

      emit(state.copyWith(
        selectedCompany: targetCompany,
        members: members,
        invitations: invitations,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, error: 'Failed to select company: $e'));
    }
  }

  Future<void> _onCreateCompany(
      CreateCompany event, Emitter<CompanyState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final result = await _authService.createCompany(event.name);
      if (result != null) {
        emit(state.copyWith(
          successMessage: 'Company "${event.name}" created!',
          isLoading: false,
        ));
        // Reload companies list and select the newly created one
        add(const LoadCompanies());
      } else {
        emit(state.copyWith(
            isLoading: false, error: 'Failed to create company'));
      }
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, error: 'Error: ${e.toString()}'));
    }
  }

  Future<void> _onDeleteCompany(
      DeleteCompany event, Emitter<CompanyState> emit) async {
    // Check if user is owner before attempting delete
    final company = state.companies.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['id']?.toString() == event.companyId,
          orElse: () => null,
        );
    final role = company?['role']?.toString() ?? 'staff';
    if (role != 'owner') {
      emit(state.copyWith(error: 'Only owners can delete a company'));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null));
    try {
      await _authService.deleteCompany(event.companyId);
      emit(state.copyWith(
        successMessage: '"${event.companyName}" deleted',
        isLoading: false,
      ));
      add(const LoadCompanies());
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, error: 'Error: ${e.toString()}'));
    }
  }

  Future<void> _onLeaveCompany(
      LeaveCompany event, Emitter<CompanyState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await _authService.leaveCompany(event.companyId);
      emit(state.copyWith(
        successMessage: 'Left "${event.companyName}"',
        isLoading: false,
      ));
      add(const LoadCompanies());
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, error: 'Error: ${e.toString()}'));
    }
  }

  Future<void> _onJoinCompany(
      JoinCompany event, Emitter<CompanyState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final result = await _authService.acceptInvitation(event.token);
      // FIX 1: `result` can be null — use ?[] (null-aware index) so the
      // `[]` operator is never called on a null receiver.
      if (result != null && result['success'] == true) {
        emit(state.copyWith(
          successMessage: 'Company joined successfully!',
          isLoading: false,
        ));
        add(const LoadCompanies());
      } else {
        final message = result is Map<String, dynamic>
            ? (result['message']?.toString() ?? 'Invalid or expired invitation token')
            : 'Invalid or expired invitation token';
        emit(state.copyWith(isLoading: false, error: message));
      }
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, error: 'Error: ${e.toString()}'));
    }
  }

  Future<void> _onCreateInvitation(
      CreateInvitation event, Emitter<CompanyState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final result = await _authService.createInvitation(
        companyId: event.companyId,
        email: event.email,
        role: event.role,
      );
      // FIX 2: Same pattern — `result` can be null. The `is Map<String, dynamic>`
      // type-test both promotes the type AND acts as the null check, so `[]`
      // is only called after Dart knows `result` is a non-null map.
      if (result is Map<String, dynamic> && result['success'] == true) {
        emit(state.copyWith(
          isLoading: false,
          invitationToken: result['token']?.toString(),
          successMessage: 'Invitation sent to ${event.email}',
        ));
        // Reload to get updated invitations list
        add(const LoadCompanies());
      } else {
        final message = result is Map<String, dynamic>
            ? (result['message']?.toString() ?? 'Failed to create invitation')
            : 'Failed to create invitation';
        emit(state.copyWith(isLoading: false, error: message));
      }
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, error: 'Error: ${e.toString()}'));
    }
  }

  Future<void> _onCancelInvitation(
      CancelInvitation event, Emitter<CompanyState> emit) async {
    try {
      await _authService.cancelInvitation(event.invitationId);
      emit(state.copyWith(successMessage: 'Invitation cancelled'));
      add(const LoadCompanies());
    } catch (e) {
      emit(state.copyWith(error: 'Error: ${e.toString()}'));
    }
  }

  Future<void> _onRemoveMember(
      RemoveMember event, Emitter<CompanyState> emit) async {
    try {
      await _authService.removeMember(event.memberId, event.companyId);
      emit(state.copyWith(
          successMessage: '${event.memberName} removed'));
      add(const LoadCompanies());
    } catch (e) {
      emit(state.copyWith(error: 'Error: ${e.toString()}'));
    }
  }

  Future<void> _onChangeMemberRole(
      ChangeMemberRole event, Emitter<CompanyState> emit) async {
    try {
      await _authService.updateMemberRole(
          event.memberId, event.companyId, event.newRole);
      emit(state.copyWith(successMessage: 'Role updated'));
      add(const LoadCompanies());
    } catch (e) {
      emit(state.copyWith(error: 'Error: ${e.toString()}'));
    }
  }

  /// Clears success messages, errors, and invitation tokens from state.
  /// Call this after displaying a message to prevent repeated displays.
  void _onClearMessages(
      ClearMessages event, Emitter<CompanyState> emit) {
    emit(state.copyWith(
      error: null,
      successMessage: null,
      invitationToken: null,
    ));
  }
}