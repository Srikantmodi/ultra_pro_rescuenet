// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mesh_packet_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MeshPacketModelAdapter extends TypeAdapter<MeshPacketModel> {
  @override
  final int typeId = 0;

  @override
  MeshPacketModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MeshPacketModel(
      id: fields[0] as String,
      originatorId: fields[1] as String,
      payload: fields[2] as String,
      trace: (fields[3] as List).cast<String>(),
      ttl: fields[4] as int,
      timestamp: fields[5] as int,
      priority: fields[6] as int,
      packetType: fields[7] as String,
    );
  }

  @override
  void write(BinaryWriter writer, MeshPacketModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.originatorId)
      ..writeByte(2)
      ..write(obj.payload)
      ..writeByte(3)
      ..write(obj.trace)
      ..writeByte(4)
      ..write(obj.ttl)
      ..writeByte(5)
      ..write(obj.timestamp)
      ..writeByte(6)
      ..write(obj.priority)
      ..writeByte(7)
      ..write(obj.packetType);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeshPacketModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
