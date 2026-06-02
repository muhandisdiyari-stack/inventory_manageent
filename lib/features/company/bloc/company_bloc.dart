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
  }

  // ═══════════════════════════════════════════════════════════════
  // LOAD COMPANIES - Get ALL companies where user is a member
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onLoadCompanies(
      LoadCompanies event, Emitter<CompanyState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      // ✅ Get ALL companies where user is a member (not just profiles.company_id)
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

      // Keep current selection if still valid, otherwise select first
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

      // Load members and invitations for the selected company
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

  // ═══════════════════════════════════════════════════════════════
  // SELECT COMPANY - Switch active company
  // ═══════════════════════════════════════════════════════════════

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
        emit(state.copyWith(isLoading: false, error: 'Company not found'));
        return;
      }

      // ✅ FIX: Update InventoryService with new company context
      try {
        await InjectionContainer.inventoryService.setCurrentCompany(event.companyId);
        debugPrint('📋 InventoryService notified of company switch to: $event.companyId');
      } catch (e) {
        debugPrint('⚠️ Failed to update company context in InventoryService: $e');
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

  // ═══════════════════════════════════════════════════════════════
  // CREATE COMPANY
  // ═══════════════════════════════════════════════════════════════

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
        // Reload all companies to show the new one
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

  // ═══════════════════════════════════════════════════════════════
  // DELETE COMPANY
  // ═══════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════
  // LEAVE COMPANY
  // ═══════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════
  // JOIN COMPANY (via token)
  // ═══════════════════════════════════════════════════════════════

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

      final success = result['success'];
      if (success == true) {
        emit(state.copyWith(
          successMessage: 'Company joined successfully!',
          isLoading: false,
        ));
        add(const LoadCompanies());
      } else {
        final message = result['message']?.toString() ?? 'Invalid or expired invitation token';
        emit(state.copyWith(isLoading: false, error: message));
      }
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Error: ${e.toString()}',
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CREATE INVITATION
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onCreateInvitation(
      CreateInvitation event, Emitter<CompanyState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final result = await _authService.createInvitation(
        companyId: event.companyId,
        email: event.email,
        role: event.role,
      );

      debugPrint('createInvitation result: $result');

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
        emit(state.copyWith(
          isLoading: false,
          successMessage: 'Invitation sent to ${event.email}. They will see the company automatically when they sign in.',
        ));
        add(const LoadCompanies());
      } else {
        final message = result['message']?.toString() ?? 'Failed to send invitation';
        emit(state.copyWith(isLoading: false, error: message));
      }
    } catch (e) {
      debugPrint('Create invitation error: $e');
      emit(state.copyWith(
        isLoading: false,
        error: 'Error: ${e.toString()}',
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CANCEL INVITATION
  // ═══════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════
  // REMOVE MEMBER
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onRemoveMember(
      RemoveMember event, Emitter<CompanyState> emit) async {
    try {
      await _authService.removeMember(event.memberId, event.companyId);
      emit(state.copyWith(successMessage: '${event.memberName} removed'));
      add(const LoadCompanies());
    } catch (e) {
      emit(state.copyWith(error: 'Error: ${e.toString()}'));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CHANGE MEMBER ROLE
  // ═══════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════
  // CLEAR MESSAGES
  // ═══════════════════════════════════════════════════════════════

  void _onClearMessages(ClearMessages event, Emitter<CompanyState> emit) {
    emit(state.copyWith(error: null, successMessage: null));
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPER
  // ═══════════════════════════════════════════════════════════════

  Map<String, dynamic>? _findCompany(String companyId) {
    for (final c in state.companies) {
      if (c['id']?.toString() == companyId) {
        return c;
      }
    }
    return null;
  }
}