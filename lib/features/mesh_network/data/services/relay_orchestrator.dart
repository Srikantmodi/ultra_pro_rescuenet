import 'dart:async';
import 'package:rxdart/rxdart.dart';
import '../../domain/entities/mesh_packet.dart';
import '../../domain/entities/node_info.dart';
import '../../domain/services/routing/ai_router.dart';
import '../datasources/local/hive/boxes/outbox_box.dart';
import '../datasources/remote/wifi_p2p_source.dart';
import '../models/mesh_packet_model.dart';

/// The Relay Orchestrator is the background engine that keeps packets moving.
///
/// It runs a continuous loop that:
/// 1. Checks outbox for pending packets
/// 2. Waits for neighbors to be discovered
/// 3. Selects best neighbor using AI Router
/// 4. Connects, sends, waits for ACK, disconnects
/// 5. Handles retries and failures
///
/// This implements the "Store-and-Forward" protocol where packets are stored
/// locally and forwarded when a viable route becomes available.
class RelayOrchestrator {
  final WifiP2pSource _wifiP2pSource;
  final OutboxBox _outbox;
  final AiRouter _aiRouter;
  String _nodeId;

  // Relay loop control
  Timer? _relayTimer;
  bool _isRunning = false;
  bool _isProcessing = false;

  // Configuration
  static const Duration relayInterval = Duration(seconds: 10);
  static const Duration retryDelay = Duration(seconds: 30);
  static const int maxConsecutiveFailures = 3;

  // Statistics
  int _packetsSent = 0;
  int _packetsFailed = 0;
  int _consecutiveFailures = 0;

  // Stream controllers
  final _statsController = BehaviorSubject<RelayStats>.seeded(RelayStats.empty());
  final _activityController = StreamController<RelayActivity>.broadcast();

  /// Creates the relay orchestrator.
  RelayOrchestrator({
    required WifiP2pSource wifiP2pSource,
    required OutboxBox outbox,
    required String nodeId,
    AiRouter? aiRouter,
  })  : _wifiP2pSource = wifiP2pSource,
        _outbox = outbox,
        _nodeId = nodeId,
        _aiRouter = aiRouter ?? AiRouter();

  /// Stream of relay statistics.
  Stream<RelayStats> get stats => _statsController.stream;

  /// Stream of relay activity events.
  Stream<RelayActivity> get activity => _activityController.stream;

  /// Whether the relay loop is running.
  bool get isRunning => _isRunning;

  /// Sets the node ID. Must be called before [start].
  void setNodeId(String id) {
    _nodeId = id;
  }

  /// Current statistics.
  RelayStats get currentStats => _statsController.value;

  /// Starts the background relay loop.
  ///
  /// Throws [StateError] if [setNodeId] has not been called.
  void start() {
    if (_isRunning) return;

    if (_nodeId.isEmpty) {
      throw StateError(
        'RelayOrchestrator.start() called before setNodeId(). '
        'Node ID must be set during MeshBloc initialization.',
      );
    }

    _isRunning = true;
    _emitActivity(RelayActivityType.started, 'Relay orchestrator started');

    // Start periodic relay loop
    _relayTimer = Timer.periodic(relayInterval, (_) => _runRelayLoop());

    // Run immediately on start
    _runRelayLoop();
  }

  /// Stops the background relay loop.
  void stop() {
    _isRunning = false;
    _relayTimer?.cancel();
    _relayTimer = null;
    _emitActivity(RelayActivityType.stopped, 'Relay orchestrator stopped');
  }

  /// Runs one iteration of the relay loop.
  Future<void> _runRelayLoop() async {
    if (!_isRunning || _isProcessing) return;

    _isProcessing = true;
    _emitActivity(RelayActivityType.checking, 'Checking outbox...');

    try {
      // Get pending packets
      final packets = _outbox.getPendingPackets();

      if (packets.isEmpty) {
        _isProcessing = false;
        return;
      }

      _emitActivity(
        RelayActivityType.pending,
        'Found ${packets.length} pending packets',
      );

      // Get current neighbors
      final neighbors = _wifiP2pSource.currentNodes;

      if (neighbors.isEmpty) {
        _emitActivity(RelayActivityType.noNeighbors, 'No neighbors discovered');
        _isProcessing = false;
        return;
      }

      // Process packets one at a time (to avoid overwhelming the network)
      for (final packet in packets) {
        if (!_isRunning) break;

        final result = await _processPacket(packet, neighbors);

        if (result) {
          _packetsSent++;
          _consecutiveFailures = 0;
        } else {
          _packetsFailed++;
          _consecutiveFailures++;
        }

        _updateStats();

        // If too many failures, pause and wait
        if (_consecutiveFailures >= maxConsecutiveFailures) {
          _emitActivity(
            RelayActivityType.paused,
            'Pausing after $maxConsecutiveFailures consecutive failures',
          );
          await Future.delayed(retryDelay);
          _consecutiveFailures = 0;
        }

        // Small delay between packets
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      _emitActivity(RelayActivityType.error, 'Relay loop error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Processes a single packet for relay.
  Future<bool> _processPacket(MeshPacket packet, List<NodeInfo> neighbors) async {
    _emitActivity(
      RelayActivityType.processing,
      'Processing packet ${packet.id.substring(0, 8)}...',
    );

    // Check if packet is still valid
    if (!packet.isAlive) {
      _emitActivity(RelayActivityType.expired, 'Packet expired (TTL=0)');
      await _outbox.removePacket(packet.id);
      return false;
    }

    // Loop detection is handled per-target inside makeRoutingDecision

    // Select best neighbor
    final decision = _aiRouter.makeRoutingDecision(
      neighbors: neighbors,
      packet: packet,
      currentNodeId: _nodeId,
    );

    if (!decision.hasRoute) {
      final reason = _aiRouter.getRoutingFailureReason(
        neighbors: neighbors,
        packet: packet,
        currentNodeId: _nodeId,
      );
      _emitActivity(
        RelayActivityType.noRoute,
        'No viable route: ${reason ?? "unknown"}',
      );
      return false;
    }

    final targetNode = decision.selectedNode!;
    _emitActivity(
      RelayActivityType.selected,
      'Selected ${targetNode.displayName} (score: ${decision.selectedScore?.toStringAsFixed(1)})',
    );

    // Attempt to send
    final sendResult = await _attemptSend(packet, targetNode);

    if (sendResult) {
      await _outbox.markSent(packet.id);
      _emitActivity(RelayActivityType.sent, 'Packet sent successfully');
    } else {
      final canRetry = await _outbox.markFailed(packet.id);
      _emitActivity(
        RelayActivityType.failed,
        canRetry ? 'Send failed, will retry' : 'Send failed, max retries exceeded',
      );
    }

    return sendResult;
  }

  /// Attempts to send a packet to a target node using the unified
  /// connectAndSendPacket (hit-and-run) flow.
  Future<bool> _attemptSend(MeshPacket packet, NodeInfo target) async {
    try {
      // If we are the originator retrying our own packet, our node ID is
      // already in the trace (placed there by MeshPacket.create).  Calling
      // addHop would throw a StateError and silently burn all retries,
      // permanently losing the SOS.  Skip the hop — the next relay node
      // will add its own hop when it receives the packet.
      final updatedPacket = packet.hasVisited(_nodeId)
          ? packet
          : packet.addHop(_nodeId);

      _emitActivity(
        RelayActivityType.connecting,
        'Connecting to ${target.displayName} (${target.deviceAddress})...',
      );

      // Serialize packet
      final packetJson = MeshPacketModel.entityToJsonString(updatedPacket);

      // Use unified connect-and-send: native handles connect → send → ACK → disconnect
      final sendResult = await _wifiP2pSource.connectAndSendPacket(
        deviceAddress: target.deviceAddress,
        packetJson: packetJson,
      );

      return sendResult.success;

    } catch (e) {
      _emitActivity(RelayActivityType.error, 'Send error: $e');
      return false;
    }
  }

  /// Forces an immediate relay attempt.
  Future<void> forceRelay() async {
    if (_isProcessing) return;
    await _runRelayLoop();
  }

  /// Updates and emits statistics.
  void _updateStats() {
    final outboxStats = _outbox.getStats();
    _statsController.add(RelayStats(
      packetsSent: _packetsSent,
      packetsFailed: _packetsFailed,
      pendingCount: outboxStats.pending,
      neighborsCount: _wifiP2pSource.currentNodes.length,
      isRunning: _isRunning,
      consecutiveFailures: _consecutiveFailures,
    ));
  }

  /// Emits an activity event.
  void _emitActivity(RelayActivityType type, String message) {
    _activityController.add(RelayActivity(
      type: type,
      message: message,
      timestamp: DateTime.now(),
    ));
  }

  /// Disposes of resources.
  void dispose() {
    stop();
    _statsController.close();
    _activityController.close();
  }

  /// Notifies the orchestrator that a packet was forwarded outside its loop.
  /// This keeps the stats counter accurate for immediate forwards in the repository.
  void recordExternalForward() {
    _packetsSent++;
    _updateStats();
  }
}

/// Statistics about relay operations.
class RelayStats {
  final int packetsSent;
  final int packetsFailed;
  final int pendingCount;
  final int neighborsCount;
  final bool isRunning;
  final int consecutiveFailures;

  const RelayStats({
    required this.packetsSent,
    required this.packetsFailed,
    required this.pendingCount,
    required this.neighborsCount,
    required this.isRunning,
    required this.consecutiveFailures,
  });

  factory RelayStats.empty() => const RelayStats(
        packetsSent: 0,
        packetsFailed: 0,
        pendingCount: 0,
        neighborsCount: 0,
        isRunning: false,
        consecutiveFailures: 0,
      );

  double get successRate {
    final total = packetsSent + packetsFailed;
    if (total == 0) return 0.0;
    return packetsSent / total;
  }

  @override
  String toString() {
    return 'RelayStats(sent: $packetsSent, failed: $packetsFailed, '
        'pending: $pendingCount, neighbors: $neighborsCount)';
  }
}

/// A relay activity event.
class RelayActivity {
  final RelayActivityType type;
  final String message;
  final DateTime timestamp;

  const RelayActivity({
    required this.type,
    required this.message,
    required this.timestamp,
  });

  @override
  String toString() => '[${type.name}] $message';
}

/// Types of relay activity events.
enum RelayActivityType {
  started,
  stopped,
  checking,
  pending,
  noNeighbors,
  processing,
  expired,
  noRoute,
  selected,
  connecting,
  sent,
  failed,
  paused,
  error,
}
