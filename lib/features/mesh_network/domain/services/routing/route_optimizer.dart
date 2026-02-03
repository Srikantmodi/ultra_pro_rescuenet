import '../../entities/mesh_packet.dart';
import '../../entities/node_info.dart';
import 'neighbor_scorer.dart';

/// Optimizes routing decisions over time.
class RouteOptimizer {
  final NeighborScorer _scorer;
  final Map<String, RouteStats> _routeStats = {};

  RouteOptimizer({NeighborScorer? scorer})
      : _scorer = scorer ?? NeighborScorer();

  /// Optimize the selection of next hop.
  NodeInfo? optimizeSelection({
    required MeshPacket packet,
    required List<NodeInfo> candidates,
    required String currentNodeId,
  }) {
    if (candidates.isEmpty) return null;

    // Score all candidates
    final scored = candidates.map((node) {
      final baseScore = _scorer.scoreNode(
        neighbor: node,
        packet: packet,
        currentNodeId: currentNodeId,
      );
      final historyBonus = _getHistoryBonus(node.id);
      return _ScoredNode(node, baseScore + historyBonus);
    }).toList();

    // Sort by score descending
    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.first.node;
  }

  double _getHistoryBonus(String nodeId) {
    final stats = _routeStats[nodeId];
    if (stats == null) return 0.0;

    // Bonus based on success rate
    return stats.successRate * 20.0;
  }

  /// Record successful delivery through a node.
  void recordSuccess(String nodeId) {
    _routeStats.putIfAbsent(nodeId, () => RouteStats());
    _routeStats[nodeId]!.recordSuccess();
  }

  /// Record failed delivery through a node.
  void recordFailure(String nodeId) {
    _routeStats.putIfAbsent(nodeId, () => RouteStats());
    _routeStats[nodeId]!.recordFailure();
  }

  /// Get statistics for a node.
  RouteStats? getStats(String nodeId) => _routeStats[nodeId];

  /// Clear all statistics.
  void clear() => _routeStats.clear();
}

class _ScoredNode {
  final NodeInfo node;
  final double score;

  _ScoredNode(this.node, this.score);
}

/// Statistics for a route/node.
class RouteStats {
  int successCount = 0;
  int failureCount = 0;
  DateTime? lastSuccess;
  DateTime? lastFailure;

  int get totalAttempts => successCount + failureCount;

  double get successRate {
    if (totalAttempts == 0) return 0.5;
    return successCount / totalAttempts;
  }

  void recordSuccess() {
    successCount++;
    lastSuccess = DateTime.now();
  }

  void recordFailure() {
    failureCount++;
    lastFailure = DateTime.now();
  }
}
