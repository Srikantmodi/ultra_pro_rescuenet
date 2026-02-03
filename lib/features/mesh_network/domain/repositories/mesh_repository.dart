import '../entities/mesh_packet.dart';
import '../entities/node_info.dart';

/// Repository interface for mesh network operations.
abstract class MeshRepository {
  /// Initialize the mesh network.
  Future<void> initialize();

  /// Start the mesh network (discovery + relay).
  Future<void> start();

  /// Stop the mesh network.
  Future<void> stop();

  /// Send an SOS packet.
  Future<bool> sendSos({
    required String payload,
    required String originatorId,
  });

  /// Send a packet to the network.
  Future<bool> sendPacket(MeshPacket packet);

  /// Process an incoming packet.
  Future<void> processIncomingPacket(MeshPacket packet);

  /// Get discovered neighbors.
  List<NodeInfo> getNeighbors();

  /// Stream of neighbor updates.
  Stream<List<NodeInfo>> get neighborsStream;

  /// Stream of received packets.
  Stream<MeshPacket> get packetsStream;

  /// Stream of SOS alerts.
  Stream<MeshPacket> get sosAlertsStream;

  /// Get current node info.
  NodeInfo get currentNode;

  /// Update current node metadata.
  Future<void> updateMetadata(NodeInfo nodeInfo);

  /// Check if mesh is running.
  bool get isRunning;

  /// Check internet connectivity.
  Future<bool> hasInternet();

  /// Dispose resources.
  void dispose();
}
