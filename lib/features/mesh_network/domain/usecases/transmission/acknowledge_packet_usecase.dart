import '../../entities/mesh_packet.dart';
import '../../repositories/mesh_repository.dart';

/// Use case for acknowledging a received packet.
class AcknowledgePacketUseCase {
  final MeshRepository _repository;
  final String _myNodeId;

  AcknowledgePacketUseCase({
    required MeshRepository repository,
    required String myNodeId,
  })  : _repository = repository,
        _myNodeId = myNodeId;

  /// Execute the use case.
  Future<bool> call(MeshPacket originalPacket) async {
    // Create ACK packet
    // Create ACK packet
    final ackPacket = MeshPacket.create(
      id: '${originalPacket.id}-ack',
      originatorId: _myNodeId,
      payload: originalPacket.id,
      packetType: MeshPacket.typeAck,
      priority: originalPacket.priority,
    );

    // Send ACK back
    return _repository.sendPacket(ackPacket);
  }
}
