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
      selectedCompany: selectedCompany ?? this.selectedCompany,
      members: members ?? this.members,
      invitations: invitations ?? this.invitations,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanyState &&
          isLoading == other.isLoading &&
          error == other.error &&
          successMessage == other.successMessage &&
          _mapEquals(selectedCompany, other.selectedCompany);

  @override
  int get hashCode => Object.hash(
        isLoading,
        error,
        successMessage,
        selectedCompany?['id'],
      );

  static bool _mapEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null) return b == null;
    if (b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}