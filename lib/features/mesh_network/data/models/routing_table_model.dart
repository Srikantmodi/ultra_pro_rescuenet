import 'package:equatable/equatable.dart';

/// Model for storing routing table entries.
class RoutingTableModel extends Equatable {
  final String destinationId;
  final String nextHopId;
  final int hopCount;
  final double score;
  final int lastUpdatedMs;
  final bool isActive;

  const RoutingTableModel({
    required this.destinationId,
    required this.nextHopId,
    required this.hopCount,
    required this.score,
    required this.lastUpdatedMs,
    this.isActive = true,
  });

  /// Create from JSON.
  factory RoutingTableModel.fromJson(Map<String, dynamic> json) {
    return RoutingTableModel(
      destinationId: json['destinationId'] as String,
      nextHopId: json['nextHopId'] as String,
      hopCount: json['hopCount'] as int? ?? 1,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      lastUpdatedMs: json['lastUpdatedMs'] as int? ?? 0,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'destinationId': destinationId,
      'nextHopId': nextHopId,
      'hopCount': hopCount,
      'score': score,
      'lastUpdatedMs': lastUpdatedMs,
      'isActive': isActive,
    };
  }

  /// Create a new route entry.
  factory RoutingTableModel.create({
    required String destinationId,
    required String nextHopId,
    int hopCount = 1,
    double score = 0.0,
  }) {
    return RoutingTableModel(
      destinationId: destinationId,
      nextHopId: nextHopId,
      hopCount: hopCount,
      score: score,
      lastUpdatedMs: DateTime.now().millisecondsSinceEpoch,
      isActive: true,
    );
  }

  /// Create updated copy.
  RoutingTableModel copyWith({
    String? nextHopId,
    int? hopCount,
    double? score,
    bool? isActive,
  }) {
    return RoutingTableModel(
      destinationId: destinationId,
      nextHopId: nextHopId ?? this.nextHopId,
      hopCount: hopCount ?? this.hopCount,
      score: score ?? this.score,
      lastUpdatedMs: DateTime.now().millisecondsSinceEpoch,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Check if route is stale.
  bool get isStale {
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastUpdatedMs;
    return elapsed > 5 * 60 * 1000; // 5 minutes
  }

  @override
  List<Object?> get props => [destinationId, nextHopId, hopCount];
}

/// Complete routing table.
class RoutingTable {
  final Map<String, RoutingTableModel> _routes = {};

  /// Get route to destination.
  RoutingTableModel? getRoute(String destinationId) {
    final route = _routes[destinationId];
    if (route == null || !route.isActive || route.isStale) {
      return null;
    }
    return route;
  }

  /// Update or add route.
  void updateRoute(RoutingTableModel route) {
    _routes[route.destinationId] = route;
  }

  /// Remove route.
  void removeRoute(String destinationId) {
    _routes.remove(destinationId);
  }

  /// Get all active routes.
  List<RoutingTableModel> get activeRoutes =>
      _routes.values.where((r) => r.isActive && !r.isStale).toList();

  /// Clear all routes.
  void clear() => _routes.clear();
}
