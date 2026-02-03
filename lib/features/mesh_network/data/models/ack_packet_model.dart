import 'package:equatable/equatable.dart';
import '../../domain/entities/mesh_packet.dart';

/// Model for ACK packets.
class AckPacketModel extends Equatable {
  final String originalPacketId;
  final String acknowledgedBy;
  final DateTime timestamp;
  final bool wasDelivered;
  final String? errorMessage;
  final int hopCount;

  const AckPacketModel({
    required this.originalPacketId,
    required this.acknowledgedBy,
    required this.timestamp,
    this.wasDelivered = true,
    this.errorMessage,
    this.hopCount = 0,
  });

  /// Create from JSON.
  factory AckPacketModel.fromJson(Map<String, dynamic> json) {
    return AckPacketModel(
      originalPacketId: json['originalPacketId'] as String,
      acknowledgedBy: json['acknowledgedBy'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      wasDelivered: json['wasDelivered'] as bool? ?? true,
      errorMessage: json['errorMessage'] as String?,
      hopCount: json['hopCount'] as int? ?? 0,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'originalPacketId': originalPacketId,
      'acknowledgedBy': acknowledgedBy,
      'timestamp': timestamp.toIso8601String(),
      'wasDelivered': wasDelivered,
      if (errorMessage != null) 'errorMessage': errorMessage,
      'hopCount': hopCount,
    };
  }

  /// Create from a received ACK packet.
  factory AckPacketModel.fromPacket(MeshPacket packet) {
    // The payload contains the original packet ID
    return AckPacketModel(
      originalPacketId: packet.payload,
      acknowledgedBy: packet.originatorId,
      timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestamp),
      wasDelivered: true,
      hopCount: packet.trace.length,
    );
  }

  /// Create an ACK MeshPacket for a received packet.
  static MeshPacket createAckPacket({
    required String myNodeId,
    required MeshPacket originalPacket,
  }) {
    return MeshPacket.create(
      id: '${originalPacket.id}-ack',
      originatorId: myNodeId,
      payload: originalPacket.id,
      packetType: MeshPacket.typeAck,
      priority: originalPacket.priority,
    );
  }

  @override
  List<Object?> get props => [originalPacketId, acknowledgedBy, timestamp];
}
