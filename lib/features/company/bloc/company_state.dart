part of 'company_bloc.dart';

class CompanyState {
  final List<Map<String, dynamic>> companies;
  final Map<String, dynamic>? selectedCompany;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> invitations;
  final bool isLoading;
  final String? error;
  final String? successMessage;

  const CompanyState({
    this.companies = const [],
    this.selectedCompany,
    this.members = const [],
    this.invitations = const [],
    this.isLoading = false,
    this.error,
    this.successMessage,
  });

  CompanyState copyWith({
    List<Map<String, dynamic>>? companies,
    Map<String, dynamic>? selectedCompany,
    List<Map<String, dynamic>>? members,
    List<Map<String, dynamic>>? invitations,
    bool? isLoading,
    String? error,
    String? successMessage,
  }) {
    return CompanyState(
      companies: companies ?? this.companies,
      selectedCompany: selectedCompany,
      members: members ?? this.members,
      invitations: invitations ?? this.invitations,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
    );
  }

  bool get hasCompanies => companies.isNotEmpty;
  bool get hasSelectedCompany => selectedCompany != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanyState &&
          isLoading == other.isLoading &&
          error == other.error &&
          successMessage == other.successMessage;

  @override
  int get hashCode => Object.hash(isLoading, error, successMessage);
}