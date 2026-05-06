import 'package:hive_flutter/hive_flutter.dart';

part 'inventory_settings.g.dart';

@HiveType(typeId: 2)
class FieldConfig extends HiveObject {
  @HiveField(0)
  String fieldName;
  
  @HiveField(1)
  bool isEnabled;
  
  @HiveField(2)
  bool isRequired;

  FieldConfig({
    required this.fieldName,
    this.isEnabled = true,
    this.isRequired = false,
  });
  
  FieldConfig copy() => FieldConfig(
    fieldName: fieldName,
    isEnabled: isEnabled,
    isRequired: isRequired,
  );
}

@HiveType(typeId: 3)
class InventorySettings extends HiveObject {
  @HiveField(0)
  List<FieldConfig> fieldConfigs;
  
  @HiveField(1)
  List<String> customFieldNames;

  InventorySettings({
    List<FieldConfig>? fieldConfigs,
    List<String>? customFieldNames,
  })  : fieldConfigs = fieldConfigs ?? _defaultFieldConfigs(),
        customFieldNames = customFieldNames ?? [];

  static List<FieldConfig> _defaultFieldConfigs() {
    return [
      FieldConfig(fieldName: 'Name', isEnabled: true, isRequired: true),
      FieldConfig(fieldName: 'Code', isEnabled: true, isRequired: false),
      FieldConfig(fieldName: 'Barcode', isEnabled: true, isRequired: false),
      FieldConfig(fieldName: 'Color', isEnabled: false, isRequired: false),
      FieldConfig(fieldName: 'Material', isEnabled: false, isRequired: false),
      FieldConfig(fieldName: 'Size', isEnabled: true, isRequired: false),
      FieldConfig(fieldName: 'Production Date', isEnabled: false, isRequired: false),
      FieldConfig(fieldName: 'Expire Date', isEnabled: false, isRequired: false),
      FieldConfig(fieldName: 'Note', isEnabled: true, isRequired: false),
    ];
  }

  List<FieldConfig> get activeFields => fieldConfigs.where((f) => f.isEnabled).toList();
  
  bool isFieldRequired(String fieldName) {
    final config = fieldConfigs.firstWhere(
      (f) => f.fieldName == fieldName,
      orElse: () => FieldConfig(fieldName: fieldName, isEnabled: false, isRequired: false),
    );
    return config.isRequired;
  }
  
  InventorySettings deepCopy() => InventorySettings(
    fieldConfigs: fieldConfigs.map((f) => f.copy()).toList(),
    customFieldNames: List<String>.from(customFieldNames),
  );
}