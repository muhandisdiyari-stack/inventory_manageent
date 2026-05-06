class InventoryListItem {
  final String id;
  final String name;
  final DateTime createdAt;

  InventoryListItem({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'created': createdAt.toIso8601String(),
  };

  factory InventoryListItem.fromMap(String id, Map<String, dynamic> map) {
    return InventoryListItem(
      id: id,
      name: map['name'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created'] as String? ?? '') ?? DateTime.now(),
    );
  }
}