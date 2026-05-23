part of 'company_bloc.dart';

class CompanyState {
  final List<Map<String, dynamic>> companies;
  final Map<String, dynamic>? selectedCompany;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> invitations;
  final bool isLoading;
  final String? error;
  final String? successMessage;
  final String? invitationToken;

  const CompanyState({
    this.companies = const [],
    this.selectedCompany,
    this.members = const [],
    this.invitations = const [],
    this.isLoading = false,
    this.error,
    this.successMessage,
    this.invitationToken,
  });

  CompanyState copyWith({
    List<Map<String, dynamic>>? companies,
    Map<String, dynamic>? selectedCompany,
    List<Map<String, dynamic>>? members,
    List<Map<String, dynamic>>? invitations,
    bool? isLoading,
    String? error,
    String? successMessage,
    String? invitationToken,
  }) {
    return CompanyState(
      companies: companies ?? this.companies,
      selectedCompany: selectedCompany ?? this.selectedCompany,
      members: members ?? this.members,
      invitations: invitations ?? this.invitations,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
      invitationToken: invitationToken ?? this.invitationToken,
    );
  }
}