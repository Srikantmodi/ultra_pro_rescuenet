import '../../entities/mesh_packet.dart';

/// Use case for delivering a packet that reached its final destination.
class DeliverFinalPacketUseCase {
  final void Function(MeshPacket packet)? onDelivered;

  DeliverFinalPacketUseCase({this.onDelivered});

  /// Execute the use case.
  Future<DeliveryResult> call(MeshPacket packet) async {
    // The packet has reached a node with internet
    // In a real implementation, this would upload to a server

    try {
      // Simulate delivery
      await Future.delayed(const Duration(milliseconds: 100));

      onDelivered?.call(packet);

      return DeliveryResult.success(
        packetId: packet.id,
        deliveredAt: DateTime.now(),
      );
    } catch (e) {
      return DeliveryResult.failure(
        packetId: packet.id,
        error: e.toString(),
      );
    }
  }
}

/// Result of packet delivery.
class DeliveryResult {
  final String packetId;
  final bool isSuccess;
  final DateTime? deliveredAt;
  final String? error;

  const DeliveryResult._({
    required this.packetId,
    required this.isSuccess,
    this.deliveredAt,
    this.error,
  });

  factory DeliveryResult.success({
    required String packetId,
    required DateTime deliveredAt,
  }) {
    return DeliveryResult._(
      packetId: packetId,
      isSuccess: true,
      deliveredAt: deliveredAt,
    );
  }

  factory DeliveryResult.failure({
    required String packetId,
    required String error,
  }) {
    return DeliveryResult._(
      packetId: packetId,
      isSuccess: false,
      error: error,
    );
  }
}
