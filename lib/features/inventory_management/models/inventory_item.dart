import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

part 'inventory_item.g.dart';

const _uuid = Uuid();

@HiveType(typeId: 0)
class InventoryItem extends HiveObject {
  @HiveField(0) String name;
  @HiveField(1) String code;
  @HiveField(2) String barcode;
  @HiveField(3) String color;
  @HiveField(4) String material;
  @HiveField(5) String size;
  @HiveField(6) DateTime? productionDate;
  @HiveField(7) DateTime? expireDate;
  @HiveField(8) String note;
  @HiveField(9) DateTime modified;
  @HiveField(10) int quantity;
  @HiveField(11) Map<String, String> customFields;
  @HiveField(12) String label;
  @HiveField(13) DateTime createdAt;
  @HiveField(14) String id; // NEW: UUID primary key

  // ═══════════════════════════════════════════════════════════════
  // Computed Supabase sync fields (stored in customFields)
  // ═══════════════════════════════════════════════════════════════

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

  int get rowVersion => int.tryParse(customFields['_row_version'] ?? '1') ?? 1;
  set rowVersion(int v) => _setInternal('_row_version', v.toString());

  String? get companyId => customFields['_company_id'];
  set companyId(String? v) => _setInternal('_company_id', v);

  String? get inventoryId => customFields['_inventory_id'];
  set inventoryId(String? v) => _setInternal('_inventory_id', v);

  void _setInternal(String key, String? value) {
    if (value != null) {
      customFields[key] = value;
    } else {
      customFields.remove(key);
    }
  }

  InventoryItem({
    String? id,
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
  })  : id = id ?? _uuid.v4(),
        modified = modified ?? DateTime.now(),
        customFields = customFields ?? {},
        createdAt = createdAt ?? DateTime.now() {
    if (createdBy != null) this.createdBy = createdBy;
    if (createdByName != null) this.createdByName = createdByName;
  }

  static const int maxQuantity = 999999;

  bool get isExpired =>
      expireDate != null && expireDate!.toUtc().isBefore(DateTime.now().toUtc());

  bool get isExpiringSoon {
    if (expireDate == null) return false;
    final now = DateTime.now().toUtc();
    final expiry = expireDate!.toUtc();
    return expiry.isBefore(now.add(const Duration(days: 30))) && !isExpired;
  }

  String get displayName =>
      name.isNotEmpty ? name : (size.isNotEmpty ? size : 'Unnamed');

  String get creatorDisplayName => createdByName ?? createdBy ?? 'Unknown';
  String get updaterDisplayName =>
      updatedByName ?? updatedBy ?? creatorDisplayName;

  /// Returns only user-defined custom fields (excludes internal sync fields)
  Map<String, String> get userCustomFields {
    final fields = Map<String, String>.from(customFields);
    fields.remove('_supabase_id');
    fields.remove('_created_by');
    fields.remove('_created_by_name');
    fields.remove('_updated_by');
    fields.remove('_updated_by_name');
    fields.remove('_row_version');
    fields.remove('_company_id');
    fields.remove('_inventory_id');
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

  String get formattedCreatedAt =>
      '${createdAt.year}-${_pad(createdAt.month)}-${_pad(createdAt.day)} '
      '${_pad(createdAt.hour)}:${_pad(createdAt.minute)}';

  String get formattedModifiedAt =>
      '${modified.year}-${_pad(modified.month)}-${_pad(modified.day)} '
      '${_pad(modified.hour)}:${_pad(modified.minute)}';

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// Creates a copy with updated fields for Supabase sync.
  InventoryItem copyWith({
    String? name,
    String? code,
    String? barcode,
    String? color,
    String? material,
    String? size,
    int? quantity,
    String? note,
    String? label,
    Map<String, String>? customFields,
    DateTime? productionDate,
    DateTime? expireDate,
    DateTime? modified,
  }) {
    final item = InventoryItem(
      id: id,
      name: name ?? this.name,
      code: code ?? this.code,
      barcode: barcode ?? this.barcode,
      color: color ?? this.color,
      material: material ?? this.material,
      size: size ?? this.size,
      quantity: quantity ?? this.quantity,
      note: note ?? this.note,
      label: label ?? this.label,
      customFields: customFields ?? Map<String, String>.from(this.customFields),
      productionDate: productionDate ?? this.productionDate,
      expireDate: expireDate ?? this.expireDate,
      modified: modified ?? DateTime.now(),
      createdAt: createdAt,
      createdBy: createdBy,
      createdByName: createdByName,
    );
    item.supabaseId = supabaseId;
    item.updatedBy = updatedBy;
    item.updatedByName = updatedByName;
    item.rowVersion = rowVersion;
    return item;
  }

  /// Converts to Supabase-compatible JSON map.
  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': supabaseId ?? id,
      'name': name,
      'code': code,
      'barcode': barcode,
      'color': color,
      'material': material,
      'size': size,
      'quantity': quantity,
      'note': note,
      'label': label,
      'custom_fields': userCustomFields,
      'production_date': productionDate?.toIso8601String(),
      'expire_date': expireDate?.toIso8601String(),
      'created_by': createdBy,
      'created_by_name': createdByName,
      'updated_by': updatedBy,
      'updated_by_name': updatedByName,
      'row_version': rowVersion,
    };
  }

  @override
  String toString() =>
      'InventoryItem(id: $id, name: $name, label: $label, quantity: $quantity)';
}