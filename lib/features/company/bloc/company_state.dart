part of 'company_bloc.dart';

class CompanyState {
  final List<Map<String, dynamic>> companies;
  final Map<String, dynamic>? selectedCompany;
  final bool isLoading;
  final String? error;
  final String? successMessage;

  const CompanyState({
    this.companies = const [],
    this.selectedCompany,
    this.isLoading = false,
    this.error,
    this.successMessage,
  });

  CompanyState copyWith({
    List<Map<String, dynamic>>? companies,
    Map<String, dynamic>? selectedCompany,
    bool? isLoading,
    String? error,
    String? successMessage,
  }) {
    return CompanyState(
      companies: companies ?? this.companies,
      selectedCompany: selectedCompany,
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