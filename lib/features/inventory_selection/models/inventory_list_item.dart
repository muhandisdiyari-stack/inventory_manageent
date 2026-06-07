class InventoryListItem {
  final String id;
  final String name;
  final String? role;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? createdByName;

  InventoryListItem({
    required this.id,
    required this.name,
    this.role,
    required this.createdAt,
    DateTime? modifiedAt,
    this.createdByName,
  }) : modifiedAt = modifiedAt ?? createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'role': role,
    'created': createdAt.toIso8601String(),
    'modified': modifiedAt.toIso8601String(),
    'createdByName': createdByName,
  };

  factory InventoryListItem.fromMap(String id, Map<String, dynamic> map) {
    return InventoryListItem(
      id: id,
      name: map['name'] as String? ?? '',
      role: map['role'] as String?,
      createdAt: DateTime.tryParse(
            map['created_at'] as String? ??
            map['created'] as String? ??
            '') ??
          DateTime.now(),
      modifiedAt: DateTime.tryParse(
            map['updated_at'] as String? ??
            map['modified'] as String? ??
            '') ??
          DateTime.now(),
      createdByName: map['created_by_name'] as String? ??
          map['createdByName'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is InventoryListItem && id == other.id;

  @override
  int get hashCode => id.hashCode;
}