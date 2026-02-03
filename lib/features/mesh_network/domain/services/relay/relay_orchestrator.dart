import 'dart:async';
import '../../entities/mesh_packet.dart';
import '../../entities/node_info.dart';

/// Orchestrates the packet relay process.
///
/// Domain-level relay orchestrator (pure logic).
/// See data/services/relay_orchestrator.dart for implementation.
class DomainRelayOrchestrator {
  final String nodeId;
  final StreamController<RelayEvent> _eventController =
      StreamController<RelayEvent>.broadcast();

  bool _isRunning = false;

  DomainRelayOrchestrator({required this.nodeId});

  /// Stream of relay events.
  Stream<RelayEvent> get events => _eventController.stream;

  /// Whether relay is running.
  bool get isRunning => _isRunning;

  /// Start the relay process.
  void start() {
    _isRunning = true;
    _eventController.add(RelayEvent.started());
  }

  /// Stop the relay process.
  void stop() {
    _isRunning = false;
    _eventController.add(RelayEvent.stopped());
  }

  /// Emit a relay event.
  void emit(RelayEvent event) {
    if (!_isRunning) return;
    _eventController.add(event);
  }

  /// Dispose resources.
  void dispose() {
    stop();
    _eventController.close();
  }
}

/// Events during relay process.
class RelayEvent {
  final RelayEventType type;
  final MeshPacket? packet;
  final NodeInfo? targetNode;
  final String? message;
  final DateTime timestamp;

  RelayEvent._({
    required this.type,
    this.packet,
    this.targetNode,
    this.message,
  }) : timestamp = DateTime.now();

  factory RelayEvent.started() => RelayEvent._(type: RelayEventType.started);
  factory RelayEvent.stopped() => RelayEvent._(type: RelayEventType.stopped);

  factory RelayEvent.sending(MeshPacket packet, NodeInfo target) => RelayEvent._(
        type: RelayEventType.sending,
        packet: packet,
        targetNode: target,
      );

  factory RelayEvent.success(MeshPacket packet, NodeInfo target) => RelayEvent._(
        type: RelayEventType.success,
        packet: packet,
        targetNode: target,
      );

  factory RelayEvent.failure(MeshPacket packet, String reason) => RelayEvent._(
        type: RelayEventType.failure,
        packet: packet,
        message: reason,
      );

  factory RelayEvent.noCandidate(MeshPacket packet) => RelayEvent._(
        type: RelayEventType.noCandidate,
        packet: packet,
        message: 'No forwarding candidate found',
      );
}

enum RelayEventType {
  started,
  stopped,
  sending,
  success,
  failure,
  noCandidate,
}
