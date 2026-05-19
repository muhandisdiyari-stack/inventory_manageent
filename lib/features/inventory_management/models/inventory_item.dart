import 'package:hive_flutter/hive_flutter.dart';

part 'inventory_item.g.dart';

@HiveType(typeId: 0)
class InventoryItem extends HiveObject {
  @HiveField(0)
  String name;
  
  @HiveField(1)
  String code;
  
  @HiveField(2)
  String barcode;
  
  @HiveField(3)
  String color;
  
  @HiveField(4)
  String material;
  
  @HiveField(5)
  String size;
  
  @HiveField(6)
  DateTime? productionDate;
  
  @HiveField(7)
  DateTime? expireDate;
  
  @HiveField(8)
  String note;
  
  @HiveField(9)
  DateTime modified;
  
  @HiveField(10)
  int quantity;
  
  @HiveField(11)
  Map<String, String> customFields;
  
  @HiveField(12)
  String label;
  
  @HiveField(13)
  DateTime createdAt;

  InventoryItem({
    this.name = '',
    this.code = '',
    this.barcode = '',
    this.color = '',
    this.material = '',
    this.size = '',
    this.productionDate,
    this.expireDate,
    this.note = '',
    DateTime? modified,
    this.quantity = 0,
    Map<String, String>? customFields,
    this.label = '',
    DateTime? createdAt, 
    String? createdBy,
  })  : modified = modified ?? DateTime.now(),
        customFields = customFields ?? {},
        createdAt = createdAt ?? DateTime.now();

  void updateFrom(InventoryItem other) {
    name = other.name;
    code = other.code;
    barcode = other.barcode;
    color = other.color;
    material = other.material;
    size = other.size;
    productionDate = other.productionDate;
    expireDate = other.expireDate;
    note = other.note;
    quantity = other.quantity;
    label = other.label;
    customFields = Map<String, String>.from(other.customFields);
    modified = DateTime.now();
  }

  InventoryItem copyWith({
    String? name,
    String? code,
    String? barcode,
    String? color,
    String? material,
    String? size,
    DateTime? productionDate,
    DateTime? expireDate,
    String? note,
    DateTime? modified,
    int? quantity,
    Map<String, String>? customFields,
    String? label,
    DateTime? createdAt,
  }) {
    return InventoryItem(
      name: name ?? this.name,
      code: code ?? this.code,
      barcode: barcode ?? this.barcode,
      color: color ?? this.color,
      material: material ?? this.material,
      size: size ?? this.size,
      productionDate: productionDate ?? this.productionDate,
      expireDate: expireDate ?? this.expireDate,
      note: note ?? this.note,
      modified: modified ?? DateTime.now(),
      quantity: quantity ?? this.quantity,
      customFields: customFields ?? Map<String, String>.from(this.customFields),
      label: label ?? this.label,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static const int maxQuantity = 999999;
  
  bool get isExpired {
    if (expireDate == null) return false;
    final now = DateTime.now().toUtc();
    final expiry = expireDate!.toUtc();
    return expiry.isBefore(now);
  }
  
  bool get isExpiringSoon {
    if (expireDate == null) return false;
    final now = DateTime.now().toUtc();
    final expiry = expireDate!.toUtc();
    return expiry.isBefore(now.add(const Duration(days: 30))) && !isExpired;
  }
      
  String get displayName => name.isNotEmpty ? name : (size.isNotEmpty ? size : 'Unnamed');
  
  /// Format creation date for display
  String get formattedCreatedAt {
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} '
        '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }
  
  /// Format modification date for display
  String get formattedModifiedAt {
    return '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')} '
        '${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}';
  }
  
  bool matchesQuery(String query) {
    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        code.toLowerCase().contains(q) ||
        barcode.toLowerCase().contains(q) ||
        size.toLowerCase().contains(q) ||
        label.toLowerCase().contains(q) ||
        note.toLowerCase().contains(q) ||
        color.toLowerCase().contains(q) ||
        material.toLowerCase().contains(q) ||
        customFields.values.any((v) => v.toLowerCase().contains(q));
  }
}