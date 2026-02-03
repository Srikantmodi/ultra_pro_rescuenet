import '../../entities/mesh_packet.dart';
import '../../entities/node_info.dart';

/// Strategy for forwarding packets.
abstract class ForwardingStrategy {
  /// Decide how to forward a packet.
  ForwardingDecision decide({
    required MeshPacket packet,
    required List<NodeInfo> neighbors,
    required String myNodeId,
  });
}

/// Default forwarding strategy using AI router.
class DefaultForwardingStrategy implements ForwardingStrategy {
  @override
  ForwardingDecision decide({
    required MeshPacket packet,
    required List<NodeInfo> neighbors,
    required String myNodeId,
  }) {
    // Check if packet is expired
    if (!packet.isAlive) {
      return ForwardingDecision.drop('Packet TTL expired');
    }

    // Check if I'm the destination (has internet)
    // For SOS, we deliver to any node with internet
    final myNode = neighbors.firstWhere(
      (n) => n.id == myNodeId,
      orElse: () => NodeInfo.empty(),
    );

    if (myNode.hasInternet && packet.type == PacketType.sos) {
      return ForwardingDecision.deliver('Node has internet access');
    }

    // Filter out nodes already in trace
    final candidates = neighbors
        .where((n) => !packet.hasVisited(n.id))
        .where((n) => n.isAvailableForRelay)
        .where((n) => !n.isStale)
        .toList();

    if (candidates.isEmpty) {
      return ForwardingDecision.drop('No available forwarding candidates');
    }

    // Prioritize nodes with internet
    final withInternet = candidates.where((n) => n.hasInternet).toList();
    if (withInternet.isNotEmpty) {
      return ForwardingDecision.forward(
        withInternet.first,
        'Forwarding to node with internet',
      );
    }

    // Sort by battery then signal
    candidates.sort((a, b) {
      if (a.batteryLevel != b.batteryLevel) {
        return b.batteryLevel.compareTo(a.batteryLevel);
      }
      return b.signalStrength.compareTo(a.signalStrength);
    });

    return ForwardingDecision.forward(
      candidates.first,
      'Forwarding to best available candidate',
    );
  }
}

/// Decision about how to handle a packet.
class ForwardingDecision {
  final ForwardingAction action;
  final NodeInfo? targetNode;
  final String reason;

  const ForwardingDecision._({
    required this.action,
    this.targetNode,
    required this.reason,
  });

  factory ForwardingDecision.forward(NodeInfo target, String reason) {
    return ForwardingDecision._(
      action: ForwardingAction.forward,
      targetNode: target,
      reason: reason,
    );
  }

  factory ForwardingDecision.deliver(String reason) {
    return ForwardingDecision._(
      action: ForwardingAction.deliver,
      reason: reason,
    );
  }

  factory ForwardingDecision.drop(String reason) {
    return ForwardingDecision._(
      action: ForwardingAction.drop,
      reason: reason,
    );
  }

  bool get shouldForward => action == ForwardingAction.forward;
  bool get shouldDeliver => action == ForwardingAction.deliver;
  bool get shouldDrop => action == ForwardingAction.drop;
}

enum ForwardingAction { forward, deliver, drop }
