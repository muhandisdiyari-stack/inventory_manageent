import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/di/injection_container.dart';

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
    on<RefreshCompanyData>(_onRefreshCompanyData);
  }

  Future<void> _onLoadCompanies(
      LoadCompanies event, Emitter<CompanyState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final companies = await _authService.getUserCompanies();
      debugPrint('📋 Loaded ${companies.length} companies from company_members');

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

      final currentSelectedId = state.selectedCompany?['id']?.toString();
      Map<String, dynamic>? targetCompany;

      if (currentSelectedId != null) {
        for (final c in companies) {
          if (c['id']?.toString() == currentSelectedId) {
            targetCompany = c;
            break;
          }
        }
      }

      targetCompany ??= companies.first;

      List<Map<String, dynamic>> members = [];
      List<Map<String, dynamic>> invitations = [];
      final companyId = targetCompany['id']?.toString();

      if (companyId != null && companyId.isNotEmpty) {
        try {
          members = await _authService.getCompanyMembers(companyId);
        } catch (e) {
          debugPrint('Failed to load members: $e');
        }
        try {
          invitations = await _authService.getPendingInvitations(companyId);
        } catch (e) {
          debugPrint('Failed to load invitations: $e');
        }

        try {
          await InjectionContainer.inventoryService.setCurrentCompany(companyId);
        } catch (e) {
          debugPrint('⚠️ Failed to set company context: $e');
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
        isLoading: false,
        error: 'Failed to load companies: $e',
      ));
    }
  }

  Future<void> _onSelectCompany(
      SelectCompany event, Emitter<CompanyState> emit) async {
    if (state.selectedCompany?['id']?.toString() == event.companyId &&
        state.members.isNotEmpty) {
      return;
    }

    emit(state.copyWith(isLoading: true, error: null));
    try {
      Map<String, dynamic>? targetCompany;
      for (final c in state.companies) {
        if (c['id']?.toString() == event.companyId) {
          targetCompany = c;
          break;
        }
      }

      if (targetCompany == null) {
        add(const LoadCompanies());
        return;
      }

      try {
        await InjectionContainer.inventoryService.setCurrentCompany(event.companyId);
      } catch (e) {
        debugPrint('⚠️ Failed to update company context: $e');
      }

      List<Map<String, dynamic>> members = [];
      List<Map<String, dynamic>> invitations = [];
      try {
        members = await _authService.getCompanyMembers(event.companyId);
      } catch (e) {
        debugPrint('Failed to load members: $e');
      }
      try {
        invitations = await _authService.getPendingInvitations(event.companyId);
      } catch (e) {
        debugPrint('Failed to load invitations: $e');
      }

      emit(state.copyWith(
        selectedCompany: targetCompany,
        members: members,
        invitations: invitations,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to select company: $e',
      ));
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
        add(const LoadCompanies());
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: 'Failed to create company',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Error: ${e.toString()}',
      ));
    }
  }

  Future<void> _onDeleteCompany(
      DeleteCompany event, Emitter<CompanyState> emit) async {
    final company = _findCompany(event.companyId);
    final role = company?['role']?.toString() ?? 'viewer';
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
        isLoading: false,
        error: 'Error: ${e.toString()}',
      ));
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
        isLoading: false,
        error: 'Error: ${e.toString()}',
      ));
    }
  }

  Future<void> _onJoinCompany(
      JoinCompany event, Emitter<CompanyState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final result = await _authService.acceptInvitation(event.token);

      if (result == null) {
        emit(state.copyWith(
          isLoading: false,
          error: 'Invalid or expired invitation token',
        ));
        return;
      }

      if (result['success'] == true) {
        emit(state.copyWith(
          successMessage: 'Company joined successfully!',
          isLoading: false,
        ));
        add(const LoadCompanies());
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: result['message']?.toString() ?? 'Invalid or expired invitation token',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Error: ${e.toString()}',
      ));
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
        inventoryId: event.inventoryId,
      );

      if (result == null) {
        emit(state.copyWith(
          isLoading: false,
          error: 'Failed to send invitation. Please try again.',
        ));
        return;
      }

      final success = result['success'];
      final isSuccess = success == true || success?.toString() == 'true';

      if (isSuccess) {
        final msg = event.inventoryId != null
            ? 'Invitation sent to ${event.email} for specific inventory.'
            : 'Invitation sent to ${event.email}.';
        emit(state.copyWith(
          isLoading: false,
          successMessage: msg,
        ));
        add(const LoadCompanies());
      } else {
        final message =
            result['message']?.toString() ?? 'Failed to send invitation';
        emit(state.copyWith(isLoading: false, error: message));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Error: ${e.toString()}',
      ));
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
      emit(state.copyWith(successMessage: '${event.memberName} removed'));
      add(RefreshCompanyData(companyId: event.companyId));
    } catch (e) {
      emit(state.copyWith(error: 'Error: ${e.toString()}'));
    }
  }

  Future<void> _onChangeMemberRole(
      ChangeMemberRole event, Emitter<CompanyState> emit) async {
    try {
      await _authService.updateMemberRole(
          event.memberId, event.companyId, event.newRole);
      emit(state.copyWith(successMessage: 'Role updated to ${event.newRole}'));
      add(RefreshCompanyData(companyId: event.companyId));
    } catch (e) {
      emit(state.copyWith(error: 'Error: ${e.toString()}'));
    }
  }

  Future<void> _onRefreshCompanyData(
      RefreshCompanyData event, Emitter<CompanyState> emit) async {
    try {
      List<Map<String, dynamic>> members = [];
      List<Map<String, dynamic>> invitations = [];
      try {
        members = await _authService.getCompanyMembers(event.companyId);
      } catch (e) {
        debugPrint('Failed to load members: $e');
      }
      try {
        invitations =
            await _authService.getPendingInvitations(event.companyId);
      } catch (e) {
        debugPrint('Failed to load invitations: $e');
      }
      emit(state.copyWith(members: members, invitations: invitations));
    } catch (e) {
      debugPrint('RefreshCompanyData error: $e');
    }
  }

  void _onClearMessages(ClearMessages event, Emitter<CompanyState> emit) {
    emit(state.copyWith(error: null, successMessage: null));
  }

  Map<String, dynamic>? _findCompany(String companyId) {
    for (final c in state.companies) {
      if (c['id']?.toString() == companyId) return c;
    }
    return null;
  }
}