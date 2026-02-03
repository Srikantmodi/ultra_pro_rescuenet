import 'package:equatable/equatable.dart';
import '../../../domain/entities/mesh_packet.dart';
import '../../../domain/entities/node_info.dart';

/// Mesh BLoC state.
class MeshState extends Equatable {
  final MeshStatus status;
  final List<NodeInfo> neighbors;
  final List<MeshPacket> recentPackets;
  final List<MeshPacket> sosAlerts;
  final NodeInfo? currentNode;
  final bool isRelaying;
  final String? error;
  final MeshStatistics statistics;

  const MeshState({
    this.status = MeshStatus.inactive,
    this.neighbors = const [],
    this.recentPackets = const [],
    this.sosAlerts = const [],
    this.currentNode,
    this.isRelaying = false,
    this.error,
    this.statistics = const MeshStatistics(),
  });

  MeshState copyWith({
    MeshStatus? status,
    List<NodeInfo>? neighbors,
    List<MeshPacket>? recentPackets,
    List<MeshPacket>? sosAlerts,
    NodeInfo? currentNode,
    bool? isRelaying,
    String? error,
    MeshStatistics? statistics,
  }) {
    return MeshState(
      status: status ?? this.status,
      neighbors: neighbors ?? this.neighbors,
      recentPackets: recentPackets ?? this.recentPackets,
      sosAlerts: sosAlerts ?? this.sosAlerts,
      currentNode: currentNode ?? this.currentNode,
      isRelaying: isRelaying ?? this.isRelaying,
      error: error,
      statistics: statistics ?? this.statistics,
    );
  }

  bool get isActive => status == MeshStatus.active;
  bool get hasInternet => currentNode?.hasInternet ?? false;
  int get neighborCount => neighbors.length;

  @override
  List<Object?> get props => [
        status,
        neighbors,
        recentPackets,
        sosAlerts,
        currentNode,
        isRelaying,
        error,
        statistics,
      ];
}

/// Mesh network status.
enum MeshStatus {
  inactive,
  initializing,
  active,
  error,
}

/// Mesh statistics.
class MeshStatistics extends Equatable {
  final int packetsSent;
  final int packetsReceived;
  final int packetsRelayed;
  final int sosReceived;
  final int duplicatesDropped;

  const MeshStatistics({
    this.packetsSent = 0,
    this.packetsReceived = 0,
    this.packetsRelayed = 0,
    this.sosReceived = 0,
    this.duplicatesDropped = 0,
  });

  MeshStatistics copyWith({
    int? packetsSent,
    int? packetsReceived,
    int? packetsRelayed,
    int? sosReceived,
    int? duplicatesDropped,
  }) {
    return MeshStatistics(
      packetsSent: packetsSent ?? this.packetsSent,
      packetsReceived: packetsReceived ?? this.packetsReceived,
      packetsRelayed: packetsRelayed ?? this.packetsRelayed,
      sosReceived: sosReceived ?? this.sosReceived,
      duplicatesDropped: duplicatesDropped ?? this.duplicatesDropped,
    );
  }

  @override
  List<Object?> get props => [
        packetsSent,
        packetsReceived,
        packetsRelayed,
        sosReceived,
        duplicatesDropped,
      ];
}
