import 'dart:convert';
import 'package:hive/hive.dart';
import '../../domain/entities/mesh_packet.dart';

part 'mesh_packet_model.g.dart';

/// Data model for MeshPacket with JSON and Hive serialization.
///
/// This model bridges the domain entity [MeshPacket] with:
/// - JSON encoding/decoding for network transmission
/// - Hive persistence for local storage (outbox, inbox)
///
/// The model uses Hive's TypeAdapter for efficient binary storage.
@HiveType(typeId: 0)
class MeshPacketModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String originatorId;

  @HiveField(2)
  final String payload;

  @HiveField(3)
  final List<String> trace;

  @HiveField(4)
  final int ttl;

  @HiveField(5)
  final int timestamp;

  @HiveField(6)
  final int priority;

  @HiveField(7)
  final String packetType;

  MeshPacketModel({
    required this.id,
    required this.originatorId,
    required this.payload,
    required this.trace,
    required this.ttl,
    required this.timestamp,
    required this.priority,
    required this.packetType,
  });

  /// Creates a model from the domain entity.
  factory MeshPacketModel.fromEntity(MeshPacket entity) {
    return MeshPacketModel(
      id: entity.id,
      originatorId: entity.originatorId,
      payload: entity.payload,
      trace: List<String>.from(entity.trace),
      ttl: entity.ttl,
      timestamp: entity.timestamp,
      priority: entity.priority,
      packetType: entity.packetType,
    );
  }

  /// Converts to domain entity.
  MeshPacket toEntity() {
    return MeshPacket(
      id: id,
      originatorId: originatorId,
      payload: payload,
      trace: List<String>.unmodifiable(trace),
      ttl: ttl,
      timestamp: timestamp,
      priority: priority,
      packetType: packetType,
    );
  }

  /// Creates from JSON map (for network deserialization).
  factory MeshPacketModel.fromJson(Map<String, dynamic> json) {
    return MeshPacketModel(
      id: json['id'] as String,
      originatorId: json['originatorId'] as String,
      payload: json['payload'] as String,
      trace: List<String>.from(json['trace'] as List),
      ttl: json['ttl'] as int,
      timestamp: json['timestamp'] as int,
      priority: json['priority'] as int,
      packetType: json['packetType'] as String,
    );
  }

  /// Converts to JSON map (for network transmission).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originatorId': originatorId,
      'payload': payload,
      'trace': trace,
      'ttl': ttl,
      'timestamp': timestamp,
      'priority': priority,
      'packetType': packetType,
    };
  }

  /// Creates from JSON string.
  factory MeshPacketModel.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return MeshPacketModel.fromJson(json);
  }

  /// Converts to JSON string for socket transmission.
  String toJsonString() => jsonEncode(toJson());

  /// Creates from domain entity and returns JSON string.
  /// Convenience method for transmission.
  static String entityToJsonString(MeshPacket entity) {
    return MeshPacketModel.fromEntity(entity).toJsonString();
  }

  /// Creates domain entity from JSON string.
  /// Convenience method for reception.
  static MeshPacket entityFromJsonString(String jsonString) {
    return MeshPacketModel.fromJsonString(jsonString).toEntity();
  }

  @override
  String toString() {
    return 'MeshPacketModel('
        'id: ${id.substring(0, 8)}..., '
        'from: $originatorId, '
        'type: $packetType, '
        'ttl: $ttl, '
        'trace: [${trace.join(" → ")}]'
        ')';
  }
}


