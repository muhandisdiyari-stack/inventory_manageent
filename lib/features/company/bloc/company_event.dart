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

class LeaveCompany extends CompanyEvent {
  final String companyId;
  final String companyName;
  const LeaveCompany(this.companyId, this.companyName);
}

class JoinCompany extends CompanyEvent {
  final String token;
  const JoinCompany(this.token);
}

class CreateInvitation extends CompanyEvent {
  final String companyId;
  final String email;
  final String role;
  const CreateInvitation({
    required this.companyId,
    required this.email,
    this.role = 'data_operator',
  });
}

class CancelInvitation extends CompanyEvent {
  final String invitationId;
  const CancelInvitation(this.invitationId);
}

class RemoveMember extends CompanyEvent {
  final String memberId;
  final String companyId;
  final String memberName;
  const RemoveMember({
    required this.memberId,
    required this.companyId,
    required this.memberName,
  });
}

class ChangeMemberRole extends CompanyEvent {
  final String memberId;
  final String companyId;
  final String newRole;
  const ChangeMemberRole({
    required this.memberId,
    required this.companyId,
    required this.newRole,
  });
}

class ClearMessages extends CompanyEvent {
  const ClearMessages();
}