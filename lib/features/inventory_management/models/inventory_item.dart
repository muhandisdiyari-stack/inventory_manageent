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

  // ─── User Tracking (stored in customFields) ──────────────────

  String? get supabaseId => customFields['_supabase_id'];
  set supabaseId(String? v) => _setInternal('_supabase_id', v);

  String? get createdBy => customFields['_created_by'];
  set createdBy(String? v) => _setInternal('_created_by', v);

  String? get createdByName => customFields['_created_by_name'];
  set createdByName(String? v) => _setInternal('_created_by_name', v);

  String? get updatedBy => customFields['_updated_by'];
  set updatedBy(String? v) => _setInternal('_updated_by', v);

  String? get updatedByName => customFields['_updated_by_name'];
  set updatedByName(String? v) => _setInternal('_updated_by_name', v);

  int get updateCount => int.tryParse(customFields['_update_count'] ?? '0') ?? 0;
  set updateCount(int v) => _setInternal('_update_count', v.toString());

  int get rowVersion => int.tryParse(customFields['_row_version'] ?? '1') ?? 1;
  set rowVersion(int v) => _setInternal('_row_version', v.toString());

  bool get hasReachedUpdateLimit => updateCount >= 3;

  void _setInternal(String key, String? value) {
    if (value != null) {
      customFields[key] = value;
    } else {
      customFields.remove(key);
    }
  }

  // ─── Constructor ─────────────────────────────────────────────

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
    String? createdByName,
  })  : modified = modified ?? DateTime.now(),
        customFields = customFields ?? {},
        createdAt = createdAt ?? DateTime.now() {
    if (createdBy != null) this.createdBy = createdBy;
    if (createdByName != null) this.createdByName = createdByName;
  }

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

  static const int maxQuantity = 999999;

  bool get isExpired {
    if (expireDate == null) return false;
    return expireDate!.toUtc().isBefore(DateTime.now().toUtc());
  }

  bool get isExpiringSoon {
    if (expireDate == null) return false;
    final now = DateTime.now().toUtc();
    final expiry = expireDate!.toUtc();
    return expiry.isBefore(now.add(const Duration(days: 30))) && !isExpired;
  }

  String get displayName =>
      name.isNotEmpty ? name : (size.isNotEmpty ? size : 'Unnamed');

  String get formattedCreatedAt =>
      '${createdAt.year}-${_pad(createdAt.month)}-${_pad(createdAt.day)} '
      '${_pad(createdAt.hour)}:${_pad(createdAt.minute)}';

  String get formattedModifiedAt =>
      '${modified.year}-${_pad(modified.month)}-${_pad(modified.day)} '
      '${_pad(modified.hour)}:${_pad(modified.minute)}';

  String _pad(int n) => n.toString().padLeft(2, '0');

  String get creatorDisplayName => createdByName ?? createdBy ?? 'Unknown';
  String get updaterDisplayName => updatedByName ?? updatedBy ?? creatorDisplayName;

  Map<String, String> get userCustomFields {
    final fields = Map<String, String>.from(customFields);
    fields.remove('_supabase_id');
    fields.remove('_created_by');
    fields.remove('_created_by_name');
    fields.remove('_updated_by');
    fields.remove('_updated_by_name');
    fields.remove('_update_count');
    fields.remove('_row_version');
    return fields;
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

  InventoryItem copyWith({
    String? name, String? code, String? barcode, String? color,
    String? material, String? size, DateTime? productionDate, DateTime? expireDate,
    String? note, DateTime? modified, int? quantity, Map<String, String>? customFields,
    String? label, DateTime? createdAt, String? createdBy, String? createdByName,
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
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryItem && supabaseId != null && supabaseId == other.supabaseId;

  @override
  int get hashCode => supabaseId?.hashCode ?? super.hashCode;
}