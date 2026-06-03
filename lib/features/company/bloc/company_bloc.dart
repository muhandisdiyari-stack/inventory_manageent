import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/di/injection_container.dart';

part 'company_event.dart';
part 'company_state.dart';

class CompanyBloc extends Bloc<CompanyEvent, CompanyState> {
  final AuthService _authService;
  bool _initialLoadDone = false;

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

  // ═══════════════════════════════════════════════════════════════
  // LOAD COMPANIES
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onLoadCompanies(
      LoadCompanies event, Emitter<CompanyState> emit) async {
    // Don't show full loading spinner if we already have data
    if (!_initialLoadDone || state.companies.isEmpty) {
      emit(state.copyWith(isLoading: true, error: null));
    }

    try {
      // Small delay on first load to ensure Supabase auth is fully initialized
      if (!_initialLoadDone) {
        await Future.delayed(const Duration(milliseconds: 500));
      }

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
        _initialLoadDone = true;
        return;
      }

      // Keep current selection if still valid
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

      // Only default to first company if no prior selection
      targetCompany ??= companies.first;

      // Load members and invitations for the selected company
      List<Map<String, dynamic>> members = [];
      List<Map<String, dynamic>> invitations = [];
      final companyId = targetCompany['id']?.toString();

      if (companyId != null && companyId.isNotEmpty) {
        try {
          members = await _authService.getCompanyMembers(companyId);
          debugPrint('📋 Loaded ${members.length} members for company $companyId');
        } catch (e) {
          debugPrint('Failed to load members: $e');
        }

        try {
          invitations = await _authService.getPendingInvitations(companyId);
        } catch (e) {
          debugPrint('Failed to load invitations: $e');
        }

        // Notify InventoryService of the selected company
        try {
          await InjectionContainer.inventoryService.setCurrentCompany(companyId);
          debugPrint('📋 InventoryService company context set to: $companyId');
        } catch (e) {
          debugPrint('⚠️ Failed to set company context in InventoryService: $e');
        }
      }

      _initialLoadDone = true;
      emit(state.copyWith(
        companies: companies,
        selectedCompany: targetCompany,
        members: members,
        invitations: invitations,
        isLoading: false,
      ));
    } catch (e) {
      debugPrint('❌ LoadCompanies error: $e');
      // Only show error if we have no data at all
      if (state.companies.isEmpty) {
        emit(state.copyWith(
          isLoading: false,
          error: 'Failed to load companies. Pull down to refresh.',
        ));
      } else {
        // Keep existing data, just stop loading
        emit(state.copyWith(isLoading: false));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SELECT COMPANY
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onSelectCompany(
      SelectCompany event, Emitter<CompanyState> emit) async {
    // Skip if already selected and members are loaded
    if (state.selectedCompany?['id']?.toString() == event.companyId &&
        state.members.isNotEmpty) {
      return;
    }

    emit(state.copyWith(isLoading: true, error: null));
    try {
      // Find the company in our list
      Map<String, dynamic>? targetCompany;
      for (final c in state.companies) {
        if (c['id']?.toString() == event.companyId) {
          targetCompany = c;
          break;
        }
      }

      // If company not found in list, reload all companies
      if (targetCompany == null) {
        debugPrint('📋 Company $event.companyId not in list, reloading...');
        add(const LoadCompanies());
        return;
      }

      // Update InventoryService with new company context FIRST
      try {
        await InjectionContainer.inventoryService.setCurrentCompany(event.companyId);
        debugPrint('📋 InventoryService notified of company switch to: $event.companyId');
      } catch (e) {
        debugPrint('⚠️ Failed to update company context in InventoryService: $e');
      }

      // Load members and invitations for the newly selected company
      List<Map<String, dynamic>> members = [];
      List<Map<String, dynamic>> invitations = [];

      try {
        members = await _authService.getCompanyMembers(event.companyId);
        debugPrint('📋 Loaded ${members.length} members for selected company');
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
      debugPrint('❌ SelectCompany error: $e');
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
        // Reload companies to show the new one
        _initialLoadDone = false; // Force fresh load
        add(const LoadCompanies());
      } else {
        emit(state.copyWith(
          isLoading: false,
          error: 'Failed to create company. Please try again.',
        ));
      }
    } catch (e) {
      debugPrint('❌ CreateCompany error: $e');
      emit(state.copyWith(
        isLoading: false,
        error: 'Error creating company: ${e.toString()}',
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
      emit(state.copyWith(error: 'Only company owners can delete a company'));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null));
    try {
      await _authService.deleteCompany(event.companyId);
      emit(state.copyWith(
        successMessage: '"${event.companyName}" deleted',
        isLoading: false,
      ));
      _initialLoadDone = false; // Force fresh load
      add(const LoadCompanies());
    } catch (e) {
      debugPrint('❌ DeleteCompany error: $e');
      emit(state.copyWith(
        isLoading: false,
        error: 'Error deleting company: ${e.toString()}',
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
      _initialLoadDone = false; // Force fresh load
      add(const LoadCompanies());
    } catch (e) {
      debugPrint('❌ LeaveCompany error: $e');
      emit(state.copyWith(
        isLoading: false,
        error: 'Error leaving company: ${e.toString()}',
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // JOIN COMPANY (via invitation token)
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onJoinCompany(
      JoinCompany event, Emitter<CompanyState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final result = await _authService.acceptInvitation(event.token);

      if (result == null) {
        emit(state.copyWith(
          isLoading: false,
          error: 'Invalid or expired invitation token.',
        ));
        return;
      }

      final success = result['success'];
      if (success == true) {
        emit(state.copyWith(
          successMessage: 'Company joined successfully!',
          isLoading: false,
        ));
        _initialLoadDone = false; // Force fresh load
        add(const LoadCompanies());
      } else {
        final message =
            result['message']?.toString() ?? 'Invalid or expired invitation token';
        emit(state.copyWith(isLoading: false, error: message));
      }
    } catch (e) {
      debugPrint('❌ JoinCompany error: $e');
      emit(state.copyWith(
        isLoading: false,
        error: 'Error joining company: ${e.toString()}',
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
        inventoryId: event.inventoryId,
      );

      debugPrint('📧 createInvitation result: $result');

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
            ? 'Invitation sent to ${event.email} for this inventory.'
            : 'Invitation sent to ${event.email}. They will see the company when they sign in.';
        emit(state.copyWith(
          isLoading: false,
          successMessage: msg,
        ));
        // Reload to show the new invitation in the pending list
        add(const LoadCompanies());
      } else {
        final message =
            result['message']?.toString() ?? 'Failed to send invitation';
        emit(state.copyWith(isLoading: false, error: message));
      }
    } catch (e) {
      debugPrint('❌ CreateInvitation error: $e');
      emit(state.copyWith(
        isLoading: false,
        error: 'Error sending invitation: ${e.toString()}',
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
      // Refresh company data to update the list
      final companyId = state.selectedCompany?['id']?.toString();
      if (companyId != null) {
        add(RefreshCompanyData(companyId: companyId));
      }
    } catch (e) {
      debugPrint('❌ CancelInvitation error: $e');
      emit(state.copyWith(error: 'Error cancelling invitation: ${e.toString()}'));
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
      // Refresh members list immediately
      add(RefreshCompanyData(companyId: event.companyId));
    } catch (e) {
      debugPrint('❌ RemoveMember error: $e');
      emit(state.copyWith(error: 'Error removing member: ${e.toString()}'));
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
      emit(state.copyWith(
          successMessage: 'Role updated to ${event.newRole}'));
      // Refresh members list immediately
      add(RefreshCompanyData(companyId: event.companyId));
    } catch (e) {
      debugPrint('❌ ChangeMemberRole error: $e');
      emit(state.copyWith(error: 'Error updating role: ${e.toString()}'));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // REFRESH COMPANY DATA (members + invitations only)
  // ═══════════════════════════════════════════════════════════════

  Future<void> _onRefreshCompanyData(
      RefreshCompanyData event, Emitter<CompanyState> emit) async {
    try {
      List<Map<String, dynamic>> members = [];
      List<Map<String, dynamic>> invitations = [];

      try {
        members = await _authService.getCompanyMembers(event.companyId);
      } catch (e) {
        debugPrint('Failed to load members during refresh: $e');
      }

      try {
        invitations =
            await _authService.getPendingInvitations(event.companyId);
      } catch (e) {
        debugPrint('Failed to load invitations during refresh: $e');
      }

      emit(state.copyWith(
        members: members,
        invitations: invitations,
      ));
    } catch (e) {
      debugPrint('RefreshCompanyData error: $e');
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