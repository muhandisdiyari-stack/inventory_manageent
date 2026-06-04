part of 'company_bloc.dart';

sealed class CompanyEvent {
  const CompanyEvent();
}

class LoadCompanies extends CompanyEvent {
  const LoadCompanies();
}

class SelectCompany extends CompanyEvent {
  final String companyId;
  const SelectCompany(this.companyId);
}

class CreateCompany extends CompanyEvent {
  final String name;
  const CreateCompany(this.name);
}

class DeleteCompany extends CompanyEvent {
  final String companyId;
  final String companyName;
  const DeleteCompany(this.companyId, this.companyName);
}

class ClearMessages extends CompanyEvent {
  const ClearMessages();
}

class RefreshCompanyData extends CompanyEvent {
  const RefreshCompanyData();
}