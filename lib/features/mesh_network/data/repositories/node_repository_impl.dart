import 'dart:async';
import '../../domain/entities/node_info.dart';
import '../datasources/remote/wifi_p2p_source.dart';

/// Repository implementation for node management.
class NodeRepositoryImpl {
  final WifiP2pSource _wifiP2pSource;
  final Map<String, NodeInfo> _nodesCache = {};

  NodeRepositoryImpl({required WifiP2pSource wifiP2pSource})
      : _wifiP2pSource = wifiP2pSource;

  /// Get all known neighbors.
  List<NodeInfo> getNeighbors() {
    return _nodesCache.values.where((n) => !n.isStale).toList();
  }

  /// Get a specific node by ID.
  NodeInfo? getNode(String nodeId) {
    final node = _nodesCache[nodeId];
    if (node == null || node.isStale) return null;
    return node;
  }

  /// Stream of neighbor updates.
  Stream<List<NodeInfo>> get neighborsStream => _wifiP2pSource.discoveredNodes;

  /// Update local node info.
  void updateNode(NodeInfo node) {
    _nodesCache[node.id] = node;
  }

  /// Remove stale nodes.
  void pruneStaleNodes() {
    _nodesCache.removeWhere((_, node) => node.isStale);
  }

  /// Clear all nodes.
  void clear() => _nodesCache.clear();

  /// Get node count.
  int get nodeCount => _nodesCache.length;

  /// Get nodes with internet.
  List<NodeInfo> getNodesWithInternet() {
    return _nodesCache.values
        .where((n) => n.hasInternet && !n.isStale)
        .toList();
  }

  /// Get best relay candidates (sorted by score potential).
  List<NodeInfo> getBestRelayCandidates({int limit = 5}) {
    final candidates = getNeighbors()
        .where((n) => n.isAvailableForRelay)
        .toList();

    // Sort by: internet > battery > signal
    candidates.sort((a, b) {
      if (a.hasInternet != b.hasInternet) {
        return a.hasInternet ? -1 : 1;
      }
      if (a.batteryLevel != b.batteryLevel) {
        return b.batteryLevel.compareTo(a.batteryLevel);
      }
      return b.signalStrength.compareTo(a.signalStrength);
    });

    return candidates.take(limit).toList();
  }
}
