/// Company model representing a multi-tenant organization.
///
/// Supabase is the authoritative source.
class Company {
  final String id;
  final String name;
  final String? ownerUserId;
  final String? subscriptionPlan;
  final String? companyId;
  final String? createdBy;
  final DateTime? createdAt;
  final String? modifiedBy;
  final DateTime? modifiedAt;
  final bool isSynced;
  final bool isDeleted;

  const Company({
    required this.id,
    required this.name,
    this.ownerUserId,
    this.subscriptionPlan,
    this.companyId,
    this.createdBy,
    this.createdAt,
    this.modifiedBy,
    this.modifiedAt,
    this.isSynced = false,
    this.isDeleted = false,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as String,
      name: json['name'] as String,
      ownerUserId: json['ownerUserId'] as String?,
      subscriptionPlan: json['subscriptionPlan'] as String?,
      createdBy: json['createdBy'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      companyId: json['companyId'] as String?,
      isSynced: json['isSynced'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toCloudJson() {
    return {
      'id': id,
      'name': name,
      'owner_user_id': ownerUserId,
      'subscription_plan': subscriptionPlan,
      'company_id': companyId,
    };
  }

  Map<String, dynamic> toLocalJson() {
    return {
      'id': id,
      'name': name,
      'ownerUserId': ownerUserId,
      'subscriptionPlan': subscriptionPlan,
      'companyId': companyId,
      'isSynced': isSynced,
    };
  }
}