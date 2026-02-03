import '../entities/mesh_packet.dart';
import '../entities/node_info.dart';
import '../entities/routing_entry.dart';
import '../services/routing/ai_router.dart';

/// Repository interface for routing decisions.
abstract class RoutingRepository {
  /// Get the best next hop for a packet.
  NodeInfo? getBestNextHop({
    required MeshPacket packet,
    required List<NodeInfo> neighbors,
  });

  /// Get routing decision with explanation.
  RoutingDecision getRoutingDecision({
    required MeshPacket packet,
    required List<NodeInfo> neighbors,
  });

  /// Record successful route.
  void recordSuccessfulRoute({
    required String destinationId,
    required String nextHopId,
    required int hopCount,
  });

  /// Record failed route.
  void recordFailedRoute({
    required String destinationId,
    required String nextHopId,
  });

  /// Get all active routes.
  List<RoutingEntry> getActiveRoutes();

  /// Clear all routes.
  void clearRoutes();
}
