import 'package:equatable/equatable.dart';
import '../../../domain/entities/sos_payload.dart';
import '../../../domain/entities/node_info.dart';
import '../../../domain/entities/mesh_packet.dart';

/// Mesh BLoC events.
abstract class MeshEvent extends Equatable {
  const MeshEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize mesh network.
class InitializeMesh extends MeshEvent {}

/// Start mesh network.
class StartMesh extends MeshEvent {}

/// Stop mesh network.
class StopMesh extends MeshEvent {}

/// Send SOS.
class SendSos extends MeshEvent {
  final SosPayload payload;

  const SendSos(this.payload);

  @override
  List<Object?> get props => [payload];
}

/// Update battery level.
class UpdateBattery extends MeshEvent {
  final int level;

  const UpdateBattery(this.level);

  @override
  List<Object?> get props => [level];
}

/// Update location.
class UpdateLocation extends MeshEvent {
  final double latitude;
  final double longitude;

  const UpdateLocation(this.latitude, this.longitude);

  @override
  List<Object?> get props => [latitude, longitude];
}

/// Toggle relay mode.
class ToggleRelayMode extends MeshEvent {
  final bool enabled;

  const ToggleRelayMode(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

/// Internal: Neighbors updated.
class NeighborsUpdated extends MeshEvent {
  final List<NodeInfo> neighbors;

  const NeighborsUpdated(this.neighbors);

  @override
  List<Object?> get props => [neighbors];
}

/// Internal: Packet received.
class PacketReceived extends MeshEvent {
  final MeshPacket packet;

  const PacketReceived(this.packet);

  @override
  List<Object?> get props => [packet];
}

/// Internal: Connectivity changed.
class ConnectivityChanged extends MeshEvent {
  final bool hasInternet;

  const ConnectivityChanged(this.hasInternet);

  @override
  List<Object?> get props => [hasInternet];
}
