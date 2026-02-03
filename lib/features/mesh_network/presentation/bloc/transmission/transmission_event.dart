import 'package:equatable/equatable.dart';
import '../../../domain/entities/mesh_packet.dart';

/// Transmission BLoC events.
abstract class TransmissionEvent extends Equatable {
  const TransmissionEvent();

  @override
  List<Object?> get props => [];
}

/// Send a packet.
class SendPacket extends TransmissionEvent {
  final MeshPacket packet;

  const SendPacket(this.packet);

  @override
  List<Object?> get props => [packet];
}

/// Packet sent successfully.
class PacketSent extends TransmissionEvent {
  final String packetId;
  final String targetNodeId;

  const PacketSent(this.packetId, this.targetNodeId);

  @override
  List<Object?> get props => [packetId, targetNodeId];
}

/// Packet send failed.
class PacketFailed extends TransmissionEvent {
  final String packetId;
  final String error;

  const PacketFailed(this.packetId, this.error);

  @override
  List<Object?> get props => [packetId, error];
}

/// Clear transmission history.
class ClearTransmissionHistory extends TransmissionEvent {}
