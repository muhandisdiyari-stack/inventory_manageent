import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Label model with UUID primary key.
/// Supabase is authoritative; Hive stores a cached copy only.
class Label {
  final String id;
  final String name;
  final String companyId;
  final String inventoryId;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const Label({
    required this.id,
    required this.name,
    required this.companyId,
    required this.inventoryId,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  factory Label.create({
    required String name,
    required String companyId,
    required String inventoryId,
    required String createdBy,
    required String createdByName,
  }) {
    final now = DateTime.now();
    return Label(
      id: _uuid.v4(),
      name: name,
      companyId: companyId,
      inventoryId: inventoryId,
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Label.fromSupabase(Map<String, dynamic> json) {
    return Label(
      id: json['id'] as String,
      name: json['name'] as String,
      companyId: json['company_id'] as String,
      inventoryId: json['inventory_id'] as String? ?? '',
      createdBy: json['created_by'] as String? ?? '',
      createdByName: json['created_by_name'] as String? ?? 'Unknown',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      isDeleted: json['is_deleted'] as bool? ?? false,
    );
  }

  factory Label.fromLocalJson(Map<String, dynamic> json) {
    return Label(
      id: json['id'] as String,
      name: json['name'] as String,
      companyId: json['companyId'] as String,
      inventoryId: json['inventoryId'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      createdByName: json['createdByName'] as String? ?? 'Unknown',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'name': name,
      'company_id': companyId,
      'inventory_id': inventoryId,
      'created_by': createdBy,
      'created_by_name': createdByName,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'is_deleted': isDeleted,
    };
  }

  Map<String, dynamic> toLocalJson() {
    return {
      'id': id,
      'name': name,
      'companyId': companyId,
      'inventoryId': inventoryId,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isDeleted': isDeleted,
    };
  }

  Label copyWith({
    String? name,
    String? inventoryId,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return Label(
      id: id,
      name: name ?? this.name,
      companyId: companyId,
      inventoryId: inventoryId ?? this.inventoryId,
      createdBy: createdBy,
      createdByName: createdByName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Label && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Label(id: $id, name: $name)';
}