import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Company model representing a multi-tenant organization.
///
/// Supabase is the authoritative source.
/// UUIDs are generated locally for offline creation capability,
/// but Supabase-generated UUIDs take precedence when syncing.
class Company {
  final String id;
  final String name;
  final String? ownerUserId;
  final String? subscriptionPlan;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final bool isSynced;
  final bool isDeleted;

  const Company({
    required this.id,
    required this.name,
    this.ownerUserId,
    this.subscriptionPlan,
    this.createdBy,
    this.createdAt,
    this.modifiedAt,
    this.isSynced = false,
    this.isDeleted = false,
  });

  /// Creates a new Company with a generated UUID.
  factory Company.create({
    required String name,
    String? ownerUserId,
  }) {
    return Company(
      id: _uuid.v4(),
      name: name,
      ownerUserId: ownerUserId,
      createdAt: DateTime.now(),
    );
  }

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as String? ?? _uuid.v4(),
      name: json['name'] as String,
      ownerUserId: json['owner_user_id'] as String? ??
          json['ownerUserId'] as String?,
      subscriptionPlan: json['subscription_plan'] as String? ??
          json['subscriptionPlan'] as String?,
      createdBy: json['created_by'] as String? ??
          json['createdBy'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : (json['createdAt'] != null
              ? DateTime.parse(json['createdAt'] as String)
              : null),
      isSynced: json['isSynced'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toCloudJson() {
    return {
      'id': id,
      'name': name,
      'owner_user_id': ownerUserId,
      'subscription_plan': subscriptionPlan,
      'created_by': createdBy,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toLocalJson() {
    return {
      'id': id,
      'name': name,
      'ownerUserId': ownerUserId,
      'subscriptionPlan': subscriptionPlan,
      'createdBy': createdBy,
      'createdAt': createdAt?.toIso8601String(),
      'isSynced': isSynced,
    };
  }

  Company copyWith({
    String? id,
    String? name,
    String? ownerUserId,
    String? subscriptionPlan,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return Company(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
      createdBy: createdBy,
      createdAt: createdAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Company && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Company(id: $id, name: $name)';
}