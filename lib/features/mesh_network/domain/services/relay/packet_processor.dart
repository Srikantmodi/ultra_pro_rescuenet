import '../../entities/mesh_packet.dart';
import '../../entities/node_info.dart';
import '../validation/loop_detector.dart';

/// Processes incoming packets.
class PacketProcessor {
  final LoopDetector _loopDetector;
  final String _myNodeId;

  PacketProcessor({
    required String myNodeId,
    LoopDetector? loopDetector,
  })  : _myNodeId = myNodeId,
        _loopDetector = loopDetector ?? LoopDetector();

  /// Process an incoming packet.
  ProcessingResult process({
    required MeshPacket packet,
    required Set<String> seenPackets,
    required List<NodeInfo> neighbors,
  }) {
    // Check if duplicate
    if (seenPackets.contains(packet.id)) {
      return ProcessingResult.duplicate(packet.id);
    }

    // Validate packet
    final validationResult = _loopDetector.shouldProcessPacket(
      packet: packet,
      currentNodeId: _myNodeId,
    );
    if (!validationResult.shouldProcess) {
      return ProcessingResult.rejected(
        packet.id,
        validationResult.message ?? validationResult.reason?.name ?? 'Validation failed',
      );
    }

    // Check if at destination (SOS to node with internet)
    final myNode = neighbors.firstWhere(
      (n) => n.id == _myNodeId,
      orElse: () => NodeInfo.empty(),
    );

    if (myNode.hasInternet && packet.type == PacketType.sos) {
      return ProcessingResult.delivered(packet.id);
    }

    // Check if should forward
    if (!packet.isAlive) {
      return ProcessingResult.expired(packet.id);
    }

    return ProcessingResult.forward(packet.id);
  }
}

/// Result of packet processing.
class ProcessingResult {
  final String packetId;
  final ProcessingAction action;
  final String? reason;

  const ProcessingResult._({
    required this.packetId,
    required this.action,
    this.reason,
  });

  factory ProcessingResult.duplicate(String packetId) {
    return ProcessingResult._(
      packetId: packetId,
      action: ProcessingAction.dropDuplicate,
      reason: 'Packet already seen',
    );
  }

  factory ProcessingResult.rejected(String packetId, String reason) {
    return ProcessingResult._(
      packetId: packetId,
      action: ProcessingAction.dropRejected,
      reason: reason,
    );
  }

  factory ProcessingResult.expired(String packetId) {
    return ProcessingResult._(
      packetId: packetId,
      action: ProcessingAction.dropExpired,
      reason: 'Packet TTL expired',
    );
  }

  factory ProcessingResult.delivered(String packetId) {
    return ProcessingResult._(
      packetId: packetId,
      action: ProcessingAction.delivered,
      reason: 'Packet delivered to destination',
    );
  }

  factory ProcessingResult.forward(String packetId) {
    return ProcessingResult._(
      packetId: packetId,
      action: ProcessingAction.forward,
    );
  }

  bool get shouldForward => action == ProcessingAction.forward;
  bool get wasDelivered => action == ProcessingAction.delivered;
  bool get wasDrop => action.name.startsWith('drop');
}

enum ProcessingAction {
  dropDuplicate,
  dropRejected,
  dropExpired,
  delivered,
  forward,
}
