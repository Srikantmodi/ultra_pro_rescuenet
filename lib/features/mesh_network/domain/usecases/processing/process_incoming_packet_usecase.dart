import '../../entities/mesh_packet.dart';
import '../../entities/node_info.dart';
import '../../services/validation/packet_validator.dart';

/// Use case for processing incoming packets.
class ProcessIncomingPacketUseCase {
  final PacketValidator _validator;
  final String _myNodeId;
  final Set<String> _seenPacketIds;

  ProcessIncomingPacketUseCase({
    required String myNodeId,
    PacketValidator? validator,
    Set<String>? seenPacketIds,
  })  : _myNodeId = myNodeId,
        _validator = validator ?? PacketValidator(),
        _seenPacketIds = seenPacketIds ?? {};

  /// Execute the use case.
  ProcessingResult call({
    required MeshPacket packet,
    required List<NodeInfo> neighbors,
  }) {
    // Validate packet
    final validationResult = _validator.validate(
      packet: packet,
      myNodeId: _myNodeId,
      seenPacketIds: _seenPacketIds,
    );

    if (!validationResult.isValid) {
      if (validationResult.isDuplicate) {
        return ProcessingResult.duplicate(packet.id);
      }
      return ProcessingResult.invalid(
        packet.id,
        validationResult.errors.join(', '),
      );
    }

    // Mark as seen
    _seenPacketIds.add(packet.id);

    // Check if this node should deliver (has internet + is SOS)
    final myNode = neighbors.firstWhere(
      (n) => n.id == _myNodeId,
      orElse: () => NodeInfo.empty(),
    );

    if (myNode.hasInternet && packet.type == PacketType.sos) {
      return ProcessingResult.deliver(packet.id);
    }

    // Check if packet should be forwarded
    if (!packet.isAlive) {
      return ProcessingResult.expired(packet.id);
    }

    // Add self to trace and forward
    return ProcessingResult.forward(
      packet.id,
      packet.addHop(_myNodeId),
    );
  }
}

/// Result of packet processing.
class ProcessingResult {
  final String packetId;
  final ProcessAction action;
  final String? message;
  final MeshPacket? modifiedPacket;

  const ProcessingResult._({
    required this.packetId,
    required this.action,
    this.message,
    this.modifiedPacket,
  });

  factory ProcessingResult.duplicate(String packetId) {
    return ProcessingResult._(
      packetId: packetId,
      action: ProcessAction.dropDuplicate,
      message: 'Duplicate packet',
    );
  }

  factory ProcessingResult.invalid(String packetId, String reason) {
    return ProcessingResult._(
      packetId: packetId,
      action: ProcessAction.dropInvalid,
      message: reason,
    );
  }

  factory ProcessingResult.expired(String packetId) {
    return ProcessingResult._(
      packetId: packetId,
      action: ProcessAction.dropExpired,
      message: 'TTL expired',
    );
  }

  factory ProcessingResult.deliver(String packetId) {
    return ProcessingResult._(
      packetId: packetId,
      action: ProcessAction.deliver,
      message: 'Deliver to final destination',
    );
  }

  factory ProcessingResult.forward(String packetId, MeshPacket modified) {
    return ProcessingResult._(
      packetId: packetId,
      action: ProcessAction.forward,
      modifiedPacket: modified,
    );
  }

  bool get shouldForward => action == ProcessAction.forward;
  bool get shouldDeliver => action == ProcessAction.deliver;
}

enum ProcessAction {
  dropDuplicate,
  dropInvalid,
  dropExpired,
  deliver,
  forward,
}
