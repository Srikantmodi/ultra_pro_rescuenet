import '../../entities/mesh_packet.dart';
import '../../entities/sos_payload.dart';
import '../../repositories/mesh_repository.dart';

/// Use case for broadcasting an SOS.
class BroadcastSosUseCase {
  final MeshRepository _repository;

  BroadcastSosUseCase(this._repository);

  /// Execute the use case with SOS payload.
  Future<BroadcastResult> call(SosPayload payload) async {
    final packet = MeshPacket.createSos(
      originatorId: _repository.currentNode.id,
      sosPayload: payload,
    );

    final success = await _repository.sendSos(
      payload: packet.payload,
      originatorId: packet.originatorId,
    );

    return BroadcastResult(
      packetId: packet.id,
      success: success,
      timestamp: DateTime.now(),
    );
  }

  /// Quick SOS with minimal info.
  Future<BroadcastResult> quickSos({
    required double latitude,
    required double longitude,
    String? message,
  }) async {
    final payload = SosPayload.create(
      sosId: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: _repository.currentNode.id,
      senderName: _repository.currentNode.displayName,
      latitude: latitude,
      longitude: longitude,
      emergencyType: EmergencyType.other,
      additionalNotes: message ?? 'Quick SOS',
    );

    return call(payload);
  }
}

/// Result of SOS broadcast.
class BroadcastResult {
  final String packetId;
  final bool success;
  final DateTime timestamp;
  final String? error;

  const BroadcastResult({
    required this.packetId,
    required this.success,
    required this.timestamp,
    this.error,
  });
}
