import '../../entities/node_info.dart';
import '../../entities/mesh_packet.dart';
import 'neighbor_scorer.dart';

/// The AI Router is the "Brain" of the mesh network decision plane.
///
/// It orchestrates the routing decision process:
/// 1. **Filter** - Remove ineligible nodes (stale, in trace, sender)
/// 2. **Score** - Apply Q-Learning scoring algorithm
/// 3. **Select** - Return the optimal next hop
///
/// This class provides the high-level API for the relay orchestrator to use.
class AiRouter {
  final NeighborScorer _scorer;

  /// Creates an AI Router with the given scorer.
  AiRouter({NeighborScorer? scorer}) : _scorer = scorer ?? NeighborScorer();

  /// Selects the best node from available neighbors for packet forwarding.
  ///
  /// **The Complete Routing Algorithm:**
  ///
  /// 1. **Trace Filter**: Exclude any node already in packet's trace
  /// 2. **Sender Filter**: Exclude the node that sent us this packet
  /// 3. **Stale Filter**: Exclude nodes not seen in last 2 minutes
  /// 4. **Availability Filter**: Exclude nodes not accepting relays
  /// 5. **Score**: Apply Q-Learning formula to remaining candidates
  /// 6. **Select**: Return highest-scoring node
  ///
  /// [neighbors] - List of discovered neighboring nodes from Service Discovery
  /// [packet] - The packet being routed (used for trace checking)
  /// [currentNodeId] - Our node's ID (for sender detection)
  ///
  /// Returns the best NodeInfo to forward to, or null if no viable route.
  NodeInfo? selectBestNode({
    required List<NodeInfo> neighbors,
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    // Pre-filter neighbors before scoring
    final eligibleNodes = _filterEligibleNodes(
      neighbors: neighbors,
      packet: packet,
      currentNodeId: currentNodeId,
    );

    if (eligibleNodes.isEmpty) {
      return null;
    }

    // Use scorer to rank and get best
    return _scorer.getBestCandidate(
      neighbors: eligibleNodes,
      packet: packet,
      currentNodeId: currentNodeId,
    );
  }

  /// Returns all viable routing candidates, sorted by preference.
  ///
  /// Useful for UI display showing "AI Pick" and alternatives.
  List<NodeInfo> getRoutingCandidates({
    required List<NodeInfo> neighbors,
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    final eligibleNodes = _filterEligibleNodes(
      neighbors: neighbors,
      packet: packet,
      currentNodeId: currentNodeId,
    );

    return _scorer.getViableCandidates(
      neighbors: eligibleNodes,
      packet: packet,
      currentNodeId: currentNodeId,
    );
  }

  /// Returns detailed routing decision with scores and explanations.
  ///
  /// For debugging and UI transparency.
  RoutingDecision makeRoutingDecision({
    required List<NodeInfo> neighbors,
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    final eligibleNodes = _filterEligibleNodes(
      neighbors: neighbors,
      packet: packet,
      currentNodeId: currentNodeId,
    );

    final scoredNodes = _scorer.scoreNeighbors(
      neighbors: eligibleNodes,
      packet: packet,
      currentNodeId: currentNodeId,
    );

    final explanations = <ScoringExplanation>[];
    for (final neighbor in neighbors) {
      explanations.add(_scorer.explainScore(
        neighbor: neighbor,
        packet: packet,
        currentNodeId: currentNodeId,
      ));
    }

    return RoutingDecision(
      packetId: packet.id,
      timestamp: DateTime.now(),
      totalNeighbors: neighbors.length,
      eligibleNeighbors: eligibleNodes.length,
      scoredCandidates: scoredNodes,
      explanations: explanations,
      selectedNode: scoredNodes.isNotEmpty ? scoredNodes.first.node : null,
      selectedScore: scoredNodes.isNotEmpty ? scoredNodes.first.score : null,
    );
  }

  /// Filters neighbors to only those eligible for routing.
  ///
  /// This is a "hard filter" that removes nodes that should never be
  /// considered, before the soft scoring is applied.
  List<NodeInfo> _filterEligibleNodes({
    required List<NodeInfo> neighbors,
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    return neighbors.where((node) {
      // Rule 1: Cannot be in packet trace (loop prevention)
      if (packet.hasVisited(node.id)) {
        return false;
      }

      // Rule 2: Cannot be the packet originator
      if (node.id == packet.originatorId) {
        return false;
      }

      // Rule 3: Cannot be the sender (immediate loop prevention)
      if (node.id == packet.sender) {
        return false;
      }

      // Rule 4: Must be fresh (not stale)
      if (node.isStale) {
        return false;
      }

      // Rule 5: Must be accepting relay connections
      if (!node.isAvailableForRelay) {
        return false;
      }

      return true;
    }).toList();
  }

  /// Checks if there's any viable route for the given packet.
  bool hasViableRoute({
    required List<NodeInfo> neighbors,
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    return selectBestNode(
      neighbors: neighbors,
      packet: packet,
      currentNodeId: currentNodeId,
    ) != null;
  }

  /// Checks if the packet has reached a goal node (with internet).
  ///
  /// If true, the packet should not be forwarded further.
  bool shouldDeliverHere({
    required MeshPacket packet,
    required bool currentNodeHasInternet,
  }) {
    // If this node has internet, it's the goal - deliver here
    if (currentNodeHasInternet) {
      return true;
    }

    // Otherwise, continue forwarding
    return false;
  }

  /// Returns the reason why routing failed, if it did.
  String? getRoutingFailureReason({
    required List<NodeInfo> neighbors,
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    if (neighbors.isEmpty) {
      return 'No neighbors discovered';
    }

    final eligibleNodes = _filterEligibleNodes(
      neighbors: neighbors,
      packet: packet,
      currentNodeId: currentNodeId,
    );

    if (eligibleNodes.isEmpty) {
      // Figure out why
      final allInTrace = neighbors.every((n) => packet.hasVisited(n.id));
      if (allInTrace) {
        return 'All neighbors already in packet trace';
      }

      final allStale = neighbors.every((n) => n.isStale);
      if (allStale) {
        return 'All neighbors are stale (not seen recently)';
      }

      final noneAvailable = neighbors.every((n) => !n.isAvailableForRelay);
      if (noneAvailable) {
        return 'No neighbors available for relay';
      }

      return 'All neighbors filtered out by routing rules';
    }

    final candidates = _scorer.getViableCandidates(
      neighbors: eligibleNodes,
      packet: packet,
      currentNodeId: currentNodeId,
    );

    if (candidates.isEmpty) {
      return 'All candidates scored below minimum threshold';
    }

    return null; // No failure, routing should work
  }
}

/// Represents a complete routing decision with all details.
class RoutingDecision {
  final String packetId;
  final DateTime timestamp;
  final int totalNeighbors;
  final int eligibleNeighbors;
  final List<ScoredNode> scoredCandidates;
  final List<ScoringExplanation> explanations;
  final NodeInfo? selectedNode;
  final double? selectedScore;

  const RoutingDecision({
    required this.packetId,
    required this.timestamp,
    required this.totalNeighbors,
    required this.eligibleNeighbors,
    required this.scoredCandidates,
    required this.explanations,
    this.selectedNode,
    this.selectedScore,
  });

  /// Whether a valid route was found.
  bool get hasRoute => selectedNode != null;

  /// Whether this decision routes to a goal node (with internet).
  bool get routesToGoal => selectedNode?.hasInternet ?? false;

  /// Number of candidates that passed scoring.
  int get viableCandidates => scoredCandidates.length;

  /// Nodes that were filtered out before scoring.
  int get filteredOut => totalNeighbors - eligibleNeighbors;

  @override
  String toString() {
    if (!hasRoute) {
      return 'RoutingDecision(packetId: $packetId, NO ROUTE FOUND, '
          'neighbors: $totalNeighbors, eligible: $eligibleNeighbors)';
    }
    return 'RoutingDecision('
        'packetId: $packetId, '
        'selected: ${selectedNode!.id}, '
        'score: ${selectedScore!.toStringAsFixed(1)}, '
        'toGoal: $routesToGoal, '
        'neighbors: $totalNeighbors, '
        'eligible: $eligibleNeighbors, '
        'viable: $viableCandidates'
        ')';
  }
}
