import 'package:equatable/equatable.dart';

/// Represents a single hop in a packet's trace.
class PacketTrace extends Equatable {
  final List<TraceHop> hops;

  const PacketTrace({required this.hops});

  /// Create empty trace.
  factory PacketTrace.empty() => const PacketTrace(hops: []);

  /// Create from list of node IDs.
  factory PacketTrace.fromNodeIds(List<String> nodeIds) {
    return PacketTrace(
      hops: nodeIds.asMap().entries.map((e) => TraceHop(
        nodeId: e.value,
        hopNumber: e.key + 1,
        timestamp: DateTime.now(),
      )).toList(),
    );
  }

  /// Add a hop.
  PacketTrace addHop(String nodeId) {
    return PacketTrace(
      hops: [
        ...hops,
        TraceHop(
          nodeId: nodeId,
          hopNumber: hops.length + 1,
          timestamp: DateTime.now(),
        ),
      ],
    );
  }

  /// Get node IDs as list.
  List<String> get nodeIds => hops.map((h) => h.nodeId).toList();

  /// Check if contains a node.
  bool contains(String nodeId) =>
      hops.any((h) => h.nodeId == nodeId);

  /// Get hop count.
  int get hopCount => hops.length;

  /// Check if trace has a loop.
  bool get hasLoop {
    final seen = <String>{};
    for (final hop in hops) {
      if (seen.contains(hop.nodeId)) return true;
      seen.add(hop.nodeId);
    }
    return false;
  }

  /// Get originator (first hop).
  String? get originator => hops.isNotEmpty ? hops.first.nodeId : null;

  /// Get last hop.
  String? get lastHop => hops.isNotEmpty ? hops.last.nodeId : null;

  @override
  List<Object?> get props => [hops];

  @override
  String toString() => 'PacketTrace(${nodeIds.join(' -> ')})';
}

/// A single hop in the trace.
class TraceHop extends Equatable {
  final String nodeId;
  final int hopNumber;
  final DateTime timestamp;
  final int? signalStrength;
  final int? latencyMs;

  const TraceHop({
    required this.nodeId,
    required this.hopNumber,
    required this.timestamp,
    this.signalStrength,
    this.latencyMs,
  });

  @override
  List<Object?> get props => [nodeId, hopNumber];
}
