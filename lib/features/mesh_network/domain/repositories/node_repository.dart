import '../entities/node_info.dart';

/// Repository interface for node management.
abstract class NodeRepository {
  /// Get all known neighbors.
  List<NodeInfo> getNeighbors();

  /// Get a specific node by ID.
  NodeInfo? getNode(String nodeId);

  /// Stream of neighbor updates.
  Stream<List<NodeInfo>> get neighborsStream;

  /// Update node info.
  void updateNode(NodeInfo node);

  /// Remove stale nodes.
  void pruneStaleNodes();

  /// Clear all nodes.
  void clear();

  /// Get node count.
  int get nodeCount;

  /// Get nodes with internet access.
  List<NodeInfo> getNodesWithInternet();

  /// Get best relay candidates.
  List<NodeInfo> getBestRelayCandidates({int limit = 5});
}
