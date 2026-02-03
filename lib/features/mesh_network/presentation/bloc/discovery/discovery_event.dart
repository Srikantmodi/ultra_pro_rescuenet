import 'package:equatable/equatable.dart';

/// Discovery BLoC events.
abstract class DiscoveryEvent extends Equatable {
  const DiscoveryEvent();

  @override
  List<Object?> get props => [];
}

/// Start discovery.
class StartDiscovery extends DiscoveryEvent {}

/// Stop discovery.
class StopDiscovery extends DiscoveryEvent {}

/// Neighbors updated.
class NeighborsUpdated extends DiscoveryEvent {
  final List<dynamic> neighbors;

  const NeighborsUpdated(this.neighbors);

  @override
  List<Object?> get props => [neighbors];
}

/// Refresh neighbors list.
class RefreshNeighbors extends DiscoveryEvent {}

/// Update local metadata.
class UpdateLocalMetadata extends DiscoveryEvent {
  final Map<String, dynamic> metadata;

  const UpdateLocalMetadata(this.metadata);

  @override
  List<Object?> get props => [metadata];
}
