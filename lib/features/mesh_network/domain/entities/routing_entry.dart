import 'package:equatable/equatable.dart';

/// Represents an entry in the routing table.
class RoutingEntry extends Equatable {
  /// Destination node ID.
  final String destinationId;

  /// Next hop node ID.
  final String nextHopId;

  /// Number of hops to destination.
  final int hopCount;

  /// Route score (higher is better).
  final double score;

  /// When this entry was last updated.
  final DateTime lastUpdated;

  /// Whether this route is currently active.
  final bool isActive;

  /// Success count using this route.
  final int successCount;

  /// Failure count using this route.
  final int failureCount;

  const RoutingEntry({
    required this.destinationId,
    required this.nextHopId,
    required this.hopCount,
    required this.score,
    required this.lastUpdated,
    this.isActive = true,
    this.successCount = 0,
    this.failureCount = 0,
  });

  /// Create a new routing entry.
  factory RoutingEntry.create({
    required String destinationId,
    required String nextHopId,
    int hopCount = 1,
    double score = 50.0,
  }) {
    return RoutingEntry(
      destinationId: destinationId,
      nextHopId: nextHopId,
      hopCount: hopCount,
      score: score,
      lastUpdated: DateTime.now(),
    );
  }

  /// Success rate (0.0 to 1.0).
  double get successRate {
    final total = successCount + failureCount;
    if (total == 0) return 0.5; // Unknown
    return successCount / total;
  }

  /// Whether this entry is stale (older than 5 minutes).
  bool get isStale {
    return DateTime.now().difference(lastUpdated).inMinutes > 5;
  }

  /// Record a successful delivery.
  RoutingEntry recordSuccess() {
    return _copyWith(
      successCount: successCount + 1,
      score: score + 5.0,
    );
  }

  /// Record a failed delivery.
  RoutingEntry recordFailure() {
    return _copyWith(
      failureCount: failureCount + 1,
      score: (score - 10.0).clamp(0.0, 100.0),
      isActive: failureCount + 1 < 5, // Deactivate after 5 failures
    );
  }

  RoutingEntry _copyWith({
    int? hopCount,
    double? score,
    bool? isActive,
    int? successCount,
    int? failureCount,
  }) {
    return RoutingEntry(
      destinationId: destinationId,
      nextHopId: nextHopId,
      hopCount: hopCount ?? this.hopCount,
      score: score ?? this.score,
      lastUpdated: DateTime.now(),
      isActive: isActive ?? this.isActive,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
    );
  }

  @override
  List<Object?> get props => [destinationId, nextHopId];
}
