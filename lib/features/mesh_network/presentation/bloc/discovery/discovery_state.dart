import 'package:equatable/equatable.dart';
import '../../../domain/entities/node_info.dart';

/// Discovery BLoC state.
class DiscoveryState extends Equatable {
  final bool isDiscovering;
  final List<NodeInfo> neighbors;
  final String? error;
  final DateTime? lastRefresh;

  const DiscoveryState({
    this.isDiscovering = false,
    this.neighbors = const [],
    this.error,
    this.lastRefresh,
  });

  DiscoveryState copyWith({
    bool? isDiscovering,
    List<NodeInfo>? neighbors,
    String? error,
    DateTime? lastRefresh,
  }) {
    return DiscoveryState(
      isDiscovering: isDiscovering ?? this.isDiscovering,
      neighbors: neighbors ?? this.neighbors,
      error: error,
      lastRefresh: lastRefresh ?? this.lastRefresh,
    );
  }

  int get neighborCount => neighbors.length;

  int get nodesWithInternet =>
      neighbors.where((n) => n.hasInternet).length;

  @override
  List<Object?> get props => [isDiscovering, neighbors, error, lastRefresh];
}
