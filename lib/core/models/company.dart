import 'base_entity.dart';

class Company extends BaseEntity {
  @override
  final String id;
  final String name;
  final String? ownerUserId;
  final String? subscriptionPlan;

  Company({
    required this.id,
    required this.name,
    this.ownerUserId,
    this.subscriptionPlan,
    super.createdBy,
    super.createdAt,
    super.modifiedBy,
    super.modifiedAt,
    super.isSynced,
    super.isDeleted,
    super.companyId,
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

  @override
  Map<String, dynamic> toCloudJson() {
    return {
      'id': id,
      'name': name,
      'owner_user_id': ownerUserId,
      'subscription_plan': subscriptionPlan,
      'company_id': companyId,
    };
  }

  @override
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