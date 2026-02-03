import '../../entities/mesh_packet.dart';

/// Use case for handling duplicate packets.
class HandleDuplicatePacketUseCase {
  /// Statistics
  int _duplicatesHandled = 0;

  int get duplicatesHandled => _duplicatesHandled;

  /// Execute the use case.
  DuplicateHandlingResult call(MeshPacket packet) {
    _duplicatesHandled++;

    // Just drop duplicates - nothing else to do
    return DuplicateHandlingResult(
      packetId: packet.id,
      action: DuplicateAction.dropped,
      message: 'Duplicate packet dropped',
    );
  }

  /// Reset statistics.
  void resetStats() {
    _duplicatesHandled = 0;
  }
}

/// Result of duplicate handling.
class DuplicateHandlingResult {
  final String packetId;
  final DuplicateAction action;
  final String message;

  const DuplicateHandlingResult({
    required this.packetId,
    required this.action,
    required this.message,
  });
}

enum DuplicateAction {
  dropped,
}
