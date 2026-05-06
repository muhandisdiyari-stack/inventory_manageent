// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FieldConfigAdapter extends TypeAdapter<FieldConfig> {
  @override
  final int typeId = 2;

  @override
  FieldConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FieldConfig(
      fieldName: fields[0] as String,
      isEnabled: fields[1] as bool,
      isRequired: fields[2] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, FieldConfig obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.fieldName)
      ..writeByte(1)
      ..write(obj.isEnabled)
      ..writeByte(2)
      ..write(obj.isRequired);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class InventorySettingsAdapter extends TypeAdapter<InventorySettings> {
  @override
  final int typeId = 3;

  @override
  InventorySettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InventorySettings(
      fieldConfigs: (fields[0] as List?)?.cast<FieldConfig>(),
      customFieldNames: (fields[1] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, InventorySettings obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.fieldConfigs)
      ..writeByte(1)
      ..write(obj.customFieldNames);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventorySettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
