import 'dart:async';
import 'dart:math';
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

  /// Optional callback that checks whether this node can now deliver a packet
  /// locally (e.g., node gained internet since the packet was stored in the
  /// outbox).  Returns true if it handled the packet, false to proceed with
  /// normal relay forwarding.
  Future<bool> Function(MeshPacket)? onLocalDelivery;

  // Relay loop control
  Timer? _relayTimer;
  bool _isRunning = false;
  bool _isProcessing = false;

  // Configuration
  static const Duration relayInterval = Duration(seconds: 10);
  // FIX RELAY-2.2: Replaced fixed 30s retryDelay with exponential backoff.
  // Base delay is 5 seconds, multiplied by 1.5^consecutiveFailures with jitter.
  // Capped at 30 seconds max to ensure packets don't wait too long.
  static const Duration _baseRetryDelay = Duration(seconds: 5);
  static const int _maxRetryDelaySeconds = 30;
  // FIX RELAY-2.2: Increased from 3 to 5 to give more chances before pausing.
  // With the event-driven trigger (Fix 2.1), failures due to discovery blackout
  // recover faster, so we can afford more attempts before pausing.
  static const int maxConsecutiveFailures = 5;

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

        // If too many failures, pause with exponential backoff
        if (_consecutiveFailures >= maxConsecutiveFailures) {
          final backoffDelay = _calculateRetryDelay();
          _emitActivity(
            RelayActivityType.paused,
            'Pausing ${backoffDelay.inSeconds}s after $maxConsecutiveFailures consecutive failures',
          );
          await Future.delayed(backoffDelay);
          _consecutiveFailures = 0;
        }

        // FIX: Inter-packet delay must exceed the native cooldown (5s per device)
        // to avoid COOLDOWN errors. Previously 500ms caused 4/5 packets to fail.
        // 6s ensures each packet gets a fresh cooldown window.
        if (packets.length > 1) {
          await Future.delayed(const Duration(seconds: 6));
        }
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

    // CHECK: Has this node gained internet since the packet was stored?
    // If so, deliver SOS locally (Goal path) instead of wasting a P2P
    // connection attempt to relay it to another node.
    if (onLocalDelivery != null) {
      try {
        final delivered = await onLocalDelivery!(packet);
        if (delivered) {
          _emitActivity(
            RelayActivityType.sent,
            'Delivered locally (this node is now a Goal)',
          );
          await _outbox.markSent(packet.id);
          return true;
        }
      } catch (e) {
        _emitActivity(RelayActivityType.error, 'Local delivery check error: $e');
      }
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
      // FIX RELAY-3.2: "No route" is a transient failure (neighbors may appear
      // later). Mark as transient so SOS packets don't burn real retries.
      await _outbox.markFailed(packet.id, wasTransient: true);
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

  /// FIX RELAY-2.2: Calculates retry delay with exponential backoff and jitter.
  ///
  /// Formula: base_delay * 1.5^consecutiveFailures + random(0..2000ms)
  /// Capped at [_maxRetryDelaySeconds] to prevent excessive waits.
  ///
  /// Example progression: 5s → 7.5s → 11s → 17s → 25s → 30s (capped)
  /// With jitter: 5-7s → 7.5-9.5s → 11-13s → ...
  Duration _calculateRetryDelay() {
    final baseMs = _baseRetryDelay.inMilliseconds;
    final backoffMs = (baseMs * pow(1.5, _consecutiveFailures)).toInt();
    final jitterMs = Random().nextInt(2000); // 0-2 second jitter
    final totalMs = min(backoffMs + jitterMs, _maxRetryDelaySeconds * 1000);
    return Duration(milliseconds: totalMs);
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
