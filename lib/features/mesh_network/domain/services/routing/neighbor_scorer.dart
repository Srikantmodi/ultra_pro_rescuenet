import '../../entities/node_info.dart';
import '../../entities/mesh_packet.dart';

/// The AI-powered scoring engine for mesh network routing.
///
/// This implements a Q-Learning inspired scoring algorithm that evaluates
/// neighboring nodes to find the optimal next hop for packet forwarding.
///
/// **Scoring Formula:**
/// ```
/// Score = (Internet × 50) + (SOS_Bonus × 30) + (Battery × 25) + (Signal × 10)
/// ```
///
/// The weights are pre-tuned for disaster rescue scenarios where:
/// - Internet connectivity is the ultimate goal (+50 base points)
/// - SOS packets get priority routing (+30 points if packet is SOS)
/// - Battery life ensures reliable forwarding (+25 scaled by level)
/// - Signal strength indicates connection quality (+10 scaled by dBm)
class NeighborScorer {
  /// Weight for internet connectivity bonus.
  /// Goal nodes (with internet) are the primary targets.
  static const double weightInternet = 50.0;

  /// Weight for SOS packet priority.
  /// When forwarding an SOS, nodes that can help get bonus points.
  static const double weightSosPriority = 30.0;

  /// Weight for battery level.
  /// Higher battery = more reliable relay.
  static const double weightBattery = 25.0;

  /// Weight for signal strength.
  /// Better signal = more reliable connection.
  static const double weightSignal = 10.0;

  /// Penalty for stale nodes.
  /// Nodes not seen recently are heavily penalized.
  static const double penaltyStale = -100.0;

  /// Penalty for low battery (<20%).
  /// Nodes with critically low battery may die during transfer.
  static const double penaltyLowBattery = -20.0;

  /// Penalty for nodes already in packet trace.
  /// Prevents loops - this should be infinite but we use large negative.
  static const double penaltyInTrace = -1000.0;

  /// Penalty for the sender node.
  /// Never send back to who sent it to us.
  static const double penaltySender = -1000.0;

  /// Bonus for nodes advertising as Goal role.
  static const double bonusGoalRole = 15.0;

  /// Bonus for nodes advertising as Relay role.
  static const double bonusRelayRole = 5.0;

  /// Minimum acceptable score for a node to be considered.
  static const double minimumViableScore = 0.0;

  /// Calculates the routing score for a single neighbor node.
  ///
  /// [neighbor] - The candidate node to evaluate.
  /// [packet] - The packet being forwarded (used for trace/SOS checks).
  /// [currentNodeId] - ID of the node doing the scoring (for sender detection).
  ///
  /// Returns a score where higher = better candidate.
  /// Returns negative infinity for disqualified nodes (in trace, sender, etc.)
  double scoreNode({
    required NodeInfo neighbor,
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    double score = 0.0;

    // === DISQUALIFICATION CHECKS (Hard Filters) ===

    // Rule 1: Never route to a node already in the trace (loop prevention)
    if (packet.hasVisited(neighbor.id)) {
      return penaltyInTrace;
    }

    // Rule 2: Never route back to the sender
    if (packet.sender == neighbor.id) {
      return penaltySender;
    }

    // Rule 3: Never route to the originator
    if (packet.originatorId == neighbor.id) {
      return penaltyInTrace;
    }

    // Rule 4: Penalize stale nodes heavily
    if (neighbor.isStale) {
      score += penaltyStale;
    }

    // Rule 5: Check if node is available for relay
    if (!neighbor.isAvailableForRelay) {
      return penaltyInTrace;
    }

    // === POSITIVE SCORING ===

    // Internet Bonus: The primary goal - reaching a connected node
    if (neighbor.hasInternet) {
      score += weightInternet;
    }

    // SOS Bonus: If this is an SOS packet, prioritize helpful nodes
    if (packet.isSos) {
      // Nodes with internet get extra priority for SOS
      if (neighbor.hasInternet) {
        score += weightSosPriority;
      }
      // Goal role nodes also get SOS bonus
      if (neighbor.role == NodeInfo.roleGoal) {
        score += weightSosPriority * 0.5;
      }
    }

    // Battery Score: Scaled by battery percentage (0-25 points)
    final batteryScore = weightBattery * neighbor.normalizedBattery;
    score += batteryScore;

    // Apply low battery penalty
    if (neighbor.batteryLevel < 20) {
      score += penaltyLowBattery;
    }

    // Signal Score: Scaled by signal strength (0-10 points)
    final signalScore = weightSignal * neighbor.normalizedSignal;
    score += signalScore;

    // Role Bonuses
    if (neighbor.role == NodeInfo.roleGoal) {
      score += bonusGoalRole;
    } else if (neighbor.role == NodeInfo.roleRelay) {
      score += bonusRelayRole;
    }

    return score;
  }

  /// Scores all neighbors and returns a sorted list of (node, score) pairs.
  ///
  /// [neighbors] - List of discovered neighboring nodes.
  /// [packet] - The packet to be forwarded.
  /// [currentNodeId] - ID of the node performing the routing.
  ///
  /// Returns list sorted by score (highest first), excluding disqualified nodes.
  List<ScoredNode> scoreNeighbors({
    required List<NodeInfo> neighbors,
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    final scoredNodes = <ScoredNode>[];

    for (final neighbor in neighbors) {
      final score = scoreNode(
        neighbor: neighbor,
        packet: packet,
        currentNodeId: currentNodeId,
      );

      // Only include viable candidates
      if (score > minimumViableScore) {
        scoredNodes.add(ScoredNode(node: neighbor, score: score));
      }
    }

    // Sort by score descending (highest score first)
    scoredNodes.sort((a, b) => b.score.compareTo(a.score));

    return scoredNodes;
  }

  /// Returns the best candidate node for forwarding.
  ///
  /// Returns null if no viable candidates exist.
  NodeInfo? getBestCandidate({
    required List<NodeInfo> neighbors,
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    final scored = scoreNeighbors(
      neighbors: neighbors,
      packet: packet,
      currentNodeId: currentNodeId,
    );

    if (scored.isEmpty) {
      return null;
    }

    return scored.first.node;
  }

  /// Returns all viable candidates sorted by score.
  ///
  /// Useful for displaying the "AI Pick" and alternative options in the UI.
  List<NodeInfo> getViableCandidates({
    required List<NodeInfo> neighbors,
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    final scored = scoreNeighbors(
      neighbors: neighbors,
      packet: packet,
      currentNodeId: currentNodeId,
    );

    return scored.map((s) => s.node).toList();
  }

  /// Explains the score breakdown for debugging/UI display.
  ScoringExplanation explainScore({
    required NodeInfo neighbor,
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    final components = <String, double>{};
    double total = 0.0;

    // Check disqualifications
    if (packet.hasVisited(neighbor.id)) {
      components['Loop (in trace)'] = penaltyInTrace;
      return ScoringExplanation(
        nodeId: neighbor.id,
        totalScore: penaltyInTrace,
        components: components,
        isDisqualified: true,
        reason: 'Node already in packet trace',
      );
    }

    if (packet.sender == neighbor.id) {
      components['Sender exclusion'] = penaltySender;
      return ScoringExplanation(
        nodeId: neighbor.id,
        totalScore: penaltySender,
        components: components,
        isDisqualified: true,
        reason: 'Cannot send back to sender',
      );
    }

    if (!neighbor.isAvailableForRelay) {
      return ScoringExplanation(
        nodeId: neighbor.id,
        totalScore: penaltyInTrace,
        components: {'Not available': penaltyInTrace},
        isDisqualified: true,
        reason: 'Node not available for relay',
      );
    }

    // Calculate components
    if (neighbor.isStale) {
      components['Stale penalty'] = penaltyStale;
      total += penaltyStale;
    }

    if (neighbor.hasInternet) {
      components['Internet bonus'] = weightInternet;
      total += weightInternet;
    }

    if (packet.isSos && neighbor.hasInternet) {
      components['SOS priority'] = weightSosPriority;
      total += weightSosPriority;
    }

    final batteryScore = weightBattery * neighbor.normalizedBattery;
    components['Battery (${neighbor.batteryLevel}%)'] = batteryScore;
    total += batteryScore;

    if (neighbor.batteryLevel < 20) {
      components['Low battery penalty'] = penaltyLowBattery;
      total += penaltyLowBattery;
    }

    final signalScore = weightSignal * neighbor.normalizedSignal;
    components['Signal (${neighbor.signalStrength}dBm)'] = signalScore;
    total += signalScore;

    if (neighbor.role == NodeInfo.roleGoal) {
      components['Goal role bonus'] = bonusGoalRole;
      total += bonusGoalRole;
    } else if (neighbor.role == NodeInfo.roleRelay) {
      components['Relay role bonus'] = bonusRelayRole;
      total += bonusRelayRole;
    }

    return ScoringExplanation(
      nodeId: neighbor.id,
      totalScore: total,
      components: components,
      isDisqualified: false,
      reason: null,
    );
  }
}

/// Represents a node with its calculated routing score.
class ScoredNode {
  final NodeInfo node;
  final double score;

  const ScoredNode({
    required this.node,
    required this.score,
  });

  @override
  String toString() => 'ScoredNode(${node.id}: ${score.toStringAsFixed(1)})';
}

/// Detailed breakdown of how a node's score was calculated.
class ScoringExplanation {
  final String nodeId;
  final double totalScore;
  final Map<String, double> components;
  final bool isDisqualified;
  final String? reason;

  const ScoringExplanation({
    required this.nodeId,
    required this.totalScore,
    required this.components,
    required this.isDisqualified,
    this.reason,
  });

  @override
  String toString() {
    if (isDisqualified) {
      return 'ScoringExplanation($nodeId: DISQUALIFIED - $reason)';
    }
    final parts = components.entries
        .map((e) => '${e.key}: ${e.value.toStringAsFixed(1)}')
        .join(', ');
    return 'ScoringExplanation($nodeId: ${totalScore.toStringAsFixed(1)} = [$parts])';
  }
}
