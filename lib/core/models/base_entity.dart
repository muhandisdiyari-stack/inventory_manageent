/// Base class for all multi-tenant entities.
/// Every entity that belongs to a company extends this.
abstract class BaseEntity {
  String get id;
  String? companyId;
  String? createdBy;
  DateTime? createdAt;
  String? modifiedBy;
  DateTime? modifiedAt;
  bool isSynced;
  bool isDeleted;

  BaseEntity({
    this.companyId,
    this.createdBy,
    this.createdAt,
    this.modifiedBy,
    this.modifiedAt,
    this.isSynced = false,
    this.isDeleted = false,
  });

  Map<String, dynamic> toCloudJson();
  Map<String, dynamic> toLocalJson();
}