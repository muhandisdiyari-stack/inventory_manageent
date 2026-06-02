// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class InventoryItemAdapter extends TypeAdapter<InventoryItem> {
  @override
  final int typeId = 0;

  @override
  InventoryItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return InventoryItem(
      id: fields[14] as String?,
      name: fields[0] as String,
      code: fields[1] as String,
      barcode: fields[2] as String,
      color: fields[3] as String,
      material: fields[4] as String,
      size: fields[5] as String,
      productionDate: fields[6] as DateTime?,
      expireDate: fields[7] as DateTime?,
      note: fields[8] as String,
      modified: fields[9] as DateTime?,
      quantity: fields[10] as int,
      customFields: (fields[11] as Map?)?.cast<String, String>(),
      label: fields[12] as String,
      createdAt: fields[13] as DateTime?,
    ).._isSynced = fields[23] as bool;
  }

  @override
  void write(BinaryWriter writer, InventoryItem obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.code)
      ..writeByte(2)
      ..write(obj.barcode)
      ..writeByte(3)
      ..write(obj.color)
      ..writeByte(4)
      ..write(obj.material)
      ..writeByte(5)
      ..write(obj.size)
      ..writeByte(6)
      ..write(obj.productionDate)
      ..writeByte(7)
      ..write(obj.expireDate)
      ..writeByte(8)
      ..write(obj.note)
      ..writeByte(9)
      ..write(obj.modified)
      ..writeByte(10)
      ..write(obj.quantity)
      ..writeByte(11)
      ..write(obj.customFields)
      ..writeByte(12)
      ..write(obj.label)
      ..writeByte(13)
      ..write(obj.createdAt)
      ..writeByte(14)
      ..write(obj.id)
      ..writeByte(23)
      ..write(obj._isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
