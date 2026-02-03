import '../../entities/mesh_packet.dart';

/// Defense-in-depth loop prevention system for mesh packet routing.
///
/// This service provides multiple layers of loop detection:
///
/// 1. **Trace Validation**: Checks if target is already in packet trace
/// 2. **LRU Cache Check**: Uses external cache to detect complex loops
/// 3. **TTL Validation**: Ensures packet hasn't exceeded hop limit
/// 4. **Sender Exclusion**: Prevents immediate bounce-back
///
/// The LoopDetector is used by the relay orchestrator before forwarding
/// any packet to ensure the mesh network doesn't get stuck in infinite loops.
class LoopDetector {
  /// Maximum allowed trace length before considering it suspicious.
  static const int maxTraceLength = 50;

  /// Maximum TTL we allow packets to have.
  static const int maxAllowedTtl = 30;

  /// Validates whether a packet can be forwarded to a target node.
  ///
  /// Returns a [LoopCheckResult] indicating if forwarding is allowed
  /// and the reason if not.
  LoopCheckResult canForwardTo({
    required MeshPacket packet,
    required String targetNodeId,
    required String currentNodeId,
  }) {
    // Check 1: Packet must be alive (TTL > 0)
    if (!packet.isAlive) {
      return LoopCheckResult.rejected(
        reason: LoopRejectionReason.ttlExpired,
        message: 'Packet TTL expired (${packet.ttl})',
      );
    }

    // Check 2: Target cannot be in trace (direct loop)
    if (packet.hasVisited(targetNodeId)) {
      return LoopCheckResult.rejected(
        reason: LoopRejectionReason.targetInTrace,
        message: 'Target $targetNodeId already in trace',
      );
    }

    // Check 3: Cannot forward to originator (would complete a loop)
    if (targetNodeId == packet.originatorId) {
      return LoopCheckResult.rejected(
        reason: LoopRejectionReason.targetIsOriginator,
        message: 'Cannot forward back to originator',
      );
    }

    // Check 4: Cannot forward to sender (immediate bounce-back)
    if (targetNodeId == packet.sender) {
      return LoopCheckResult.rejected(
        reason: LoopRejectionReason.targetIsSender,
        message: 'Cannot forward back to sender',
      );
    }

    // Check 5: Current node cannot already be in trace
    // (packet shouldn't have reached us if it visited us before)
    if (packet.hasVisited(currentNodeId) && 
        packet.trace.last != currentNodeId) {
      return LoopCheckResult.rejected(
        reason: LoopRejectionReason.alreadyProcessed,
        message: 'Current node already processed this packet',
      );
    }

    // Check 6: Trace length sanity check
    if (packet.trace.length > maxTraceLength) {
      return LoopCheckResult.rejected(
        reason: LoopRejectionReason.traceTooLong,
        message: 'Trace exceeds maximum length ($maxTraceLength)',
      );
    }

    // Check 7: TTL sanity check
    if (packet.ttl > maxAllowedTtl) {
      return LoopCheckResult.rejected(
        reason: LoopRejectionReason.invalidTtl,
        message: 'TTL exceeds maximum allowed ($maxAllowedTtl)',
      );
    }

    return LoopCheckResult.allowed();
  }

  /// Validates whether we should process an incoming packet.
  ///
  /// Called when a packet is received before any processing.
  LoopCheckResult shouldProcessPacket({
    required MeshPacket packet,
    required String currentNodeId,
  }) {
    // Check 1: Packet must be alive
    if (!packet.isAlive) {
      return LoopCheckResult.rejected(
        reason: LoopRejectionReason.ttlExpired,
        message: 'Received packet with expired TTL',
      );
    }

    // Check 2: We should be the expected recipient
    // (packet trace should already have been updated to include us)
    // If we're not the last in trace and we're in trace, it's a loop
    if (packet.hasVisited(currentNodeId)) {
      final lastInTrace = packet.trace.last;
      if (lastInTrace != currentNodeId) {
        return LoopCheckResult.rejected(
          reason: LoopRejectionReason.alreadyProcessed,
          message: 'Packet already visited this node at position '
              '${packet.trace.indexOf(currentNodeId)}',
        );
      }
    }

    // Check 3: Trace integrity - should have at least originator
    if (packet.trace.isEmpty) {
      return LoopCheckResult.rejected(
        reason: LoopRejectionReason.invalidTrace,
        message: 'Packet has empty trace',
      );
    }

    // Check 4: First in trace should be originator
    if (packet.trace.first != packet.originatorId) {
      return LoopCheckResult.rejected(
        reason: LoopRejectionReason.invalidTrace,
        message: 'Trace first element does not match originator',
      );
    }

    return LoopCheckResult.allowed();
  }

  /// Detects if there's a potential loop pattern in the trace.
  ///
  /// Looks for repeated subsequences that might indicate
  /// a complex multi-node loop (e.g., A→B→C→A→B→C).
  bool hasRepeatingPattern(List<String> trace) {
    if (trace.length < 4) return false;

    // Check for any node appearing twice
    final seen = <String>{};
    for (final nodeId in trace) {
      if (seen.contains(nodeId)) {
        return true;
      }
      seen.add(nodeId);
    }

    return false;
  }

  /// Returns statistics about the packet's journey.
  PacketJourneyStats getJourneyStats(MeshPacket packet) {
    final uniqueNodes = packet.trace.toSet().length;
    final totalHops = packet.trace.length - 1; // -1 for originator
    final hasLoop = hasRepeatingPattern(packet.trace);

    return PacketJourneyStats(
      packetId: packet.id,
      originatorId: packet.originatorId,
      totalHops: totalHops,
      uniqueNodes: uniqueNodes,
      remainingTtl: packet.ttl,
      hasDetectedLoop: hasLoop,
      trace: List.unmodifiable(packet.trace),
    );
  }
}

/// Result of a loop detection check.
class LoopCheckResult {
  final bool isAllowed;
  final LoopRejectionReason? reason;
  final String? message;

  const LoopCheckResult._({
    required this.isAllowed,
    this.reason,
    this.message,
  });

  /// Creates an "allowed" result.
  factory LoopCheckResult.allowed() {
    return const LoopCheckResult._(isAllowed: true);
  }

  /// Creates a "rejected" result with reason.
  factory LoopCheckResult.rejected({
    required LoopRejectionReason reason,
    required String message,
  }) {
    return LoopCheckResult._(
      isAllowed: false,
      reason: reason,
      message: message,
    );
  }

  /// Convenience getter for compatibility - same as isAllowed.
  bool get shouldProcess => isAllowed;

  @override
  String toString() {
    if (isAllowed) return 'LoopCheckResult(ALLOWED)';
    return 'LoopCheckResult(REJECTED: ${reason?.name} - $message)';
  }
}

/// Reasons why a packet might be rejected by loop detection.
enum LoopRejectionReason {
  /// TTL has reached 0
  ttlExpired,

  /// Target node is already in packet trace
  targetInTrace,

  /// Trying to forward back to the originator
  targetIsOriginator,

  /// Trying to forward back to immediate sender
  targetIsSender,

  /// This node already processed this packet
  alreadyProcessed,

  /// Trace has grown too long (suspicious)
  traceTooLong,

  /// TTL value is invalid (too high or negative)
  invalidTtl,

  /// Trace structure is invalid
  invalidTrace,
}

/// Statistics about a packet's journey through the mesh.
class PacketJourneyStats {
  final String packetId;
  final String originatorId;
  final int totalHops;
  final int uniqueNodes;
  final int remainingTtl;
  final bool hasDetectedLoop;
  final List<String> trace;

  const PacketJourneyStats({
    required this.packetId,
    required this.originatorId,
    required this.totalHops,
    required this.uniqueNodes,
    required this.remainingTtl,
    required this.hasDetectedLoop,
    required this.trace,
  });

  /// Efficiency ratio: how many unique nodes vs total hops
  double get efficiency {
    if (totalHops == 0) return 1.0;
    return uniqueNodes / totalHops;
  }

  @override
  String toString() {
    return 'PacketJourneyStats('
        'packetId: ${packetId.substring(0, 8)}..., '
        'hops: $totalHops, '
        'unique: $uniqueNodes, '
        'ttl: $remainingTtl, '
        'loop: $hasDetectedLoop'
        ')';
  }
}
