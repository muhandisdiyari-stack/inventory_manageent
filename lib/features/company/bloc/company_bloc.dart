import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/di/injection_container.dart';

part 'company_event.dart';
part 'company_state.dart';

class CompanyBloc extends Bloc<CompanyEvent, CompanyState> {
  final AuthService _authService;
  bool _initialLoadDone = false;
  bool _isLoading = false;

  CompanyBloc({required AuthService authService})
      : _authService = authService,
        super(const CompanyState()) {
    on<LoadCompanies>(_onLoadCompanies);
    on<SelectCompany>(_onSelectCompany);
    on<CreateCompany>(_onCreateCompany);
    on<DeleteCompany>(_onDeleteCompany);
    on<ClearMessages>(_onClearMessages);
    on<RefreshCompanyData>(_onRefreshCompanyData);
  }

  Future<void> _onLoadCompanies(
      LoadCompanies event, Emitter<CompanyState> emit) async {
    if (_isLoading) return;
    _isLoading = true;

    if (!_initialLoadDone || state.companies.isEmpty) {
      emit(state.copyWith(isLoading: true, error: null));
    }

    try {
      if (!_initialLoadDone) {
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final companies = await _authService.getUserCompanies();
      debugPrint(
          '📋 Loaded ${companies.length} companies (via inventory memberships)');

      if (companies.isEmpty) {
        emit(state.copyWith(
            companies: const [], selectedCompany: null, isLoading: false));
        _initialLoadDone = true;
        _isLoading = false;
        return;
      }

      final currentSelectedId =
          state.selectedCompany?['id']?.toString();
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

      final companyId = targetCompany['id']?.toString();
      if (companyId != null && companyId.isNotEmpty) {
        try {
          await InjectionContainer.inventoryService
              .setCurrentCompany(companyId);
        } catch (e) {
          debugPrint('⚠️ Failed to set company context: $e');
        }
      }

      _initialLoadDone = true;
      emit(state.copyWith(
          companies: companies,
          selectedCompany: targetCompany,
          isLoading: false));
    } catch (e) {
      debugPrint('❌ LoadCompanies error: $e');
      if (state.companies.isEmpty) {
        emit(state.copyWith(
            isLoading: false,
            error: 'Failed to load companies. Pull down to refresh.'));
      } else {
        emit(state.copyWith(isLoading: false));
      }
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _onSelectCompany(
      SelectCompany event, Emitter<CompanyState> emit) async {
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
        await InjectionContainer.inventoryService
            .setCurrentCompany(event.companyId);
      } catch (e) {
        debugPrint('⚠️ Failed to update company context: $e');
      }
      emit(state.copyWith(
          selectedCompany: targetCompany, isLoading: false));
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
            isLoading: false));
        _initialLoadDone = false;
        add(const LoadCompanies());
      } else {
        emit(state.copyWith(
            isLoading: false,
            error: 'Failed to create company. Please try again.'));
      }
    } catch (e) {
      emit(state.copyWith(
          isLoading: false,
          error: 'Error creating company: ${e.toString()}'));
    }
  }

  Future<void> _onDeleteCompany(
      DeleteCompany event, Emitter<CompanyState> emit) async {
    final company = _findCompany(event.companyId);
    final role = company?['role']?.toString() ?? 'viewer';
    if (role != 'owner') {
      emit(state.copyWith(
          error: 'Only company owners can delete a company'));
      return;
    }
    emit(state.copyWith(isLoading: true, error: null));
    try {
      await _authService.deleteCompany(event.companyId);
      emit(state.copyWith(
          successMessage: '"${event.companyName}" deleted',
          isLoading: false));
      _initialLoadDone = false;
      add(const LoadCompanies());
    } catch (e) {
      emit(state.copyWith(
          isLoading: false,
          error: 'Error deleting company: ${e.toString()}'));
    }
  }

  Future<void> _onRefreshCompanyData(
      RefreshCompanyData event, Emitter<CompanyState> emit) async {
    _initialLoadDone = false;
    add(const LoadCompanies());
  }

  void _onClearMessages(
      ClearMessages event, Emitter<CompanyState> emit) {
    emit(state.copyWith(error: null, successMessage: null));
  }

  Map<String, dynamic>? _findCompany(String companyId) {
    for (final c in state.companies) {
      if (c['id']?.toString() == companyId) return c;
    }
    return null;
  }
}