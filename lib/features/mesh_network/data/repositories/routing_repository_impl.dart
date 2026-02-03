import '../../domain/entities/node_info.dart';
import '../../domain/entities/mesh_packet.dart';
import '../../domain/services/routing/ai_router.dart';
import '../models/routing_table_model.dart';

/// Repository implementation for routing decisions.
class RoutingRepositoryImpl {
  final AiRouter _aiRouter;
  final RoutingTable _routingTable = RoutingTable();

  RoutingRepositoryImpl({required AiRouter aiRouter}) : _aiRouter = aiRouter;

  /// Get the best next hop for a packet.
  NodeInfo? getBestNextHop({
    required MeshPacket packet,
    required List<NodeInfo> neighbors,
    required String currentNodeId,
  }) {
    // First, check routing table for known good route
    for (final neighbor in neighbors) {
      if (neighbor.hasInternet) {
        return neighbor; // Direct route to internet
      }
    }

    // Use AI router for intelligent selection
    return _aiRouter.selectBestNode(
      packet: packet,
      neighbors: neighbors,
      currentNodeId: currentNodeId,
    );
  }

  /// Get routing decision with explanation.
  RoutingDecision getRoutingDecision({
    required MeshPacket packet,
    required List<NodeInfo> neighbors,
    required String currentNodeId,
  }) {
    return _aiRouter.makeRoutingDecision(
      packet: packet,
      neighbors: neighbors,
      currentNodeId: currentNodeId,
    );
  }

  /// Update routing table after successful delivery.
  void recordSuccessfulRoute({
    required String destinationId,
    required String nextHopId,
    required int hopCount,
  }) {
    final existingRoute = _routingTable.getRoute(destinationId);
    final newScore = (existingRoute?.score ?? 0.0) + 10.0;

    _routingTable.updateRoute(RoutingTableModel.create(
      destinationId: destinationId,
      nextHopId: nextHopId,
      hopCount: hopCount,
      score: newScore,
    ));
  }

  /// Update routing table after failed delivery.
  void recordFailedRoute({
    required String destinationId,
    required String nextHopId,
  }) {
    final existingRoute = _routingTable.getRoute(destinationId);
    if (existingRoute != null && existingRoute.nextHopId == nextHopId) {
      _routingTable.updateRoute(existingRoute.copyWith(
        score: existingRoute.score - 20.0,
        isActive: existingRoute.score - 20.0 > 0,
      ));
    }
  }

  /// Get all active routes.
  List<RoutingTableModel> getActiveRoutes() {
    return _routingTable.activeRoutes;
  }

  /// Clear routing table.
  void clearRoutes() => _routingTable.clear();
}
