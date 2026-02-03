import '../../entities/mesh_packet.dart';
import '../../repositories/mesh_repository.dart';
import '../../services/routing/ai_router.dart';

/// Use case for relaying a packet.
class RelayPacketUseCase {
  final MeshRepository _repository;
  final AiRouter _aiRouter;
  final String _myNodeId;

  RelayPacketUseCase({
    required MeshRepository repository,
    required AiRouter aiRouter,
    required String myNodeId,
  })  : _repository = repository,
        _aiRouter = aiRouter,
        _myNodeId = myNodeId;

  /// Execute the use case.
  Future<RelayResult> call(MeshPacket packet) async {
    // Check if packet is still alive
    if (!packet.isAlive) {
      return RelayResult.expired(packet.id);
    }

    // Get neighbors
    final neighbors = _repository.getNeighbors();

    // Find best candidate
    // Find best candidate
    final decision = _aiRouter.makeRoutingDecision(
      packet: packet,
      neighbors: neighbors,
      currentNodeId: _myNodeId, 
    );

    if (decision.selectedNode == null) {
      return RelayResult.noCandidate(
        packet.id,
        'No viable candidate found (candidates: ${decision.scoredCandidates.length})',
      );
    }

    // Add self to trace and decrement TTL
    final modifiedPacket = packet.addHop(_myNodeId);

    // Try to send
    final success = await _repository.sendPacket(modifiedPacket);

    if (success) {
      return RelayResult.success(
        packet.id,
        decision.selectedNode!.id,
        modifiedPacket.trace.length,
      );
    } else {
      return RelayResult.failure(
        packet.id,
        'Transmission failed',
      );
    }
  }
}

/// Result of relay attempt.
class RelayResult {
  final String packetId;
  final RelayAction action;
  final String? targetNodeId;
  final int? hopCount;
  final String? message;

  const RelayResult._({
    required this.packetId,
    required this.action,
    this.targetNodeId,
    this.hopCount,
    this.message,
  });

  factory RelayResult.success(String packetId, String targetId, int hops) {
    return RelayResult._(
      packetId: packetId,
      action: RelayAction.relayed,
      targetNodeId: targetId,
      hopCount: hops,
    );
  }

  factory RelayResult.failure(String packetId, String error) {
    return RelayResult._(
      packetId: packetId,
      action: RelayAction.failed,
      message: error,
    );
  }

  factory RelayResult.expired(String packetId) {
    return RelayResult._(
      packetId: packetId,
      action: RelayAction.dropped,
      message: 'TTL expired',
    );
  }

  factory RelayResult.noCandidate(String packetId, String reason) {
    return RelayResult._(
      packetId: packetId,
      action: RelayAction.queued,
      message: reason,
    );
  }

  bool get wasRelayed => action == RelayAction.relayed;
}

enum RelayAction {
  relayed,
  failed,
  dropped,
  queued,
}
