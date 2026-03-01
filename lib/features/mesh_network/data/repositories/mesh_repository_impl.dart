import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:rxdart/rxdart.dart';
import '../../domain/entities/mesh_packet.dart';
import '../../domain/entities/node_info.dart';
import '../../domain/entities/sos_payload.dart';
import '../../domain/services/routing/ai_router.dart';
import '../../domain/services/validation/loop_detector.dart';
import '../datasources/local/cache/lru_cache.dart';
import '../datasources/local/hive/boxes/outbox_box.dart';
import '../datasources/remote/wifi_p2p_source.dart';
import '../services/internet_probe.dart';
import '../services/cloud_delivery_service.dart';
import '../services/cloud_client.dart';
import '../models/mesh_packet_model.dart';

import '../../../../core/platform/location_manager.dart';

/// Repository implementation that unifies all mesh network data sources.
///
/// This is the single point of access for mesh network operations, combining:
/// - **Wi-Fi P2P Source**: Native platform channel for Wi-Fi Direct
/// - **Outbox**: Hive persistence for packets waiting to send
/// - **LRU Cache**: Duplicate packet prevention
/// - **Location Manager**: GPS coordinates
///
/// The repository implements the domain repository interface (to be created)
/// following Clean Architecture principles.
class MeshRepositoryImpl {
  final WifiP2pSource _wifiP2pSource;
  final OutboxBox _outbox;
  final SeenPacketCache _seenCache;
  final LocationManager _locationManager;
  final AiRouter _aiRouter;
  final LoopDetector _loopDetector;
  final InternetProbe _internetProbe;
  final Battery _battery;
  // ignore: unused_field
  final CloudDeliveryService _cloudDeliveryService; // Reserved for future cloud upload
  final CloudClient? _cloudClient;

  // Node ID for this device
  String? _nodeId;

  // FIX B-2: Track current role for metadata broadcast
  String _currentRole = 'r'; // Default: relay. Set to 's' for SOS sender, 'g' for goal

  // Streams
  final _meshStateController = BehaviorSubject<RepositoryState>.seeded(RepositoryState.idle);
  final _sosReceivedController = StreamController<ReceivedSos>.broadcast();
  final _relayedSosController = StreamController<ReceivedSos>.broadcast();
  final _immediateForwardController = StreamController<String>.broadcast();
  final _neighborController = BehaviorSubject<List<NodeInfo>>.seeded([]);

  // FIX RELAY-3.1: Relay diagnostics stream for debugging relay forwarding in the field.
  final _relayDiagController = StreamController<RelayDiagnostic>.broadcast();

  // Subscription management
  StreamSubscription? _packetSubscription;
  StreamSubscription? _nodeSubscription;
  Timer? _staleCleanupTimer;

  /// Creates the repository with all dependencies.
  MeshRepositoryImpl({
    required WifiP2pSource wifiP2pSource,
    required OutboxBox outbox,
    required SeenPacketCache seenCache,
    required LocationManager locationManager,
    required InternetProbe internetProbe,
    required Battery battery,
    required CloudDeliveryService cloudDeliveryService,
    CloudClient? cloudClient,
    AiRouter? aiRouter,
    LoopDetector? loopDetector,
  })  : _wifiP2pSource = wifiP2pSource,
        _outbox = outbox,
        _seenCache = seenCache,
        _locationManager = locationManager,
        _internetProbe = internetProbe,
        _battery = battery,
        _cloudDeliveryService = cloudDeliveryService,
        _cloudClient = cloudClient,
        _aiRouter = aiRouter ?? AiRouter(),
        _loopDetector = loopDetector ?? LoopDetector();

  /// Current mesh network state.
  Stream<RepositoryState> get meshState => _meshStateController.stream;

  /// Stream of received SOS alerts (Goal nodes only — has internet).
  Stream<ReceivedSos> get sosAlerts => _sosReceivedController.stream;

  /// Stream of relayed SOS alerts (Relay nodes only — no internet).
  Stream<ReceivedSos> get relayedSosAlerts => _relayedSosController.stream;

  /// Stream of packet IDs that were forwarded immediately (bypassing orchestrator).
  Stream<String> get immediateForwards => _immediateForwardController.stream;

  /// Stream of relay diagnostics for debugging forwarding decisions.
  Stream<RelayDiagnostic> get relayDiagnostics => _relayDiagController.stream;

  /// Checks if this node can now deliver a packet locally (Goal path).
  ///
  /// Called by the RelayOrchestrator before it attempts to forward a packet.
  /// If this node has gained internet since the packet was stored, and the
  /// packet is SOS, we deliver it to the Goal stream here and return true.
  /// The orchestrator then marks it as sent instead of wasting a P2P connection.
  Future<bool> tryDeliverLocally(MeshPacket packet) async {
    if (!packet.isSos) return false;

    final hasInternet = await _internetProbe.checkConnectivity(forceRefresh: true);
    if (!hasInternet) return false;

    // We are now a Goal node — deliver the SOS locally.
    print('\u2705 Orchestrator→Repository: Delivering SOS ${packet.id} locally (this node gained internet)');
    try {
      final sosPayload = SosPayload.fromJsonString(packet.payload);
      _sosReceivedController.add(ReceivedSos(
        packet: packet,
        sos: sosPayload,
        receivedAt: DateTime.now(),
        senderIp: 'local-goal-delivery',
      ));
    } catch (e) {
      print('\u26a0\ufe0f Failed to parse SOS payload for local delivery: $e');
    }

    // Also trigger cloud upload for this packet (it's already in outbox).
    _cloudClient?.syncPendingPackets().then((count) {
      if (count > 0) {
        print('\u2601\ufe0f CloudClient: $count SOS packet(s) uploaded to AWS (local-goal-delivery)');
      }
    }).catchError((e) {
      print('\u2601\ufe0f CloudClient: Upload failed — will retry: $e');
    });

    return true;
  }

  /// Stream of discovered neighbor nodes.
  Stream<List<NodeInfo>> get neighbors => _neighborController.stream;

  /// Current list of neighbors.
  List<NodeInfo> get currentNeighbors => _neighborController.value;

  /// This node's ID.
  String get nodeId => _nodeId ?? '';

  /// Initializes the mesh network system.
  ///
  /// 1. Initializes Wi-Fi P2P
  /// 2. Opens Hive boxes
  /// 3. Sets up event listeners
  /// 4. Starts location tracking
  Future<Either<Failure, void>> initialize({required String nodeId}) async {
    try {
      _nodeId = nodeId;
      _meshStateController.add(RepositoryState.initializing);

      // Initialize Wi-Fi P2P
      final wifiSuccess = await _wifiP2pSource.initialize();
      if (!wifiSuccess) {
        _meshStateController.add(RepositoryState.error);
        return Left(WifiP2pFailure('Failed to initialize Wi-Fi P2P'));
      }

      // Initialize outbox
      await _outbox.init();

      // Start location tracking
      await _locationManager.startTracking();

      // Set up event listeners
      _setupEventListeners();

      _meshStateController.add(RepositoryState.ready);
      return const Right(null);
    } catch (e) {
      _meshStateController.add(RepositoryState.error);
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  /// Starts mesh network operations.
  ///
  /// 1. Starts broadcasting our metadata
  /// 2. Starts discovering neighbors
  /// 3. Starts the packet server
  Future<Either<Failure, void>> startMesh() async {
    try {
      if (_nodeId == null) {
        return Left(ValidationFailure('Node ID not set'));
      }

      _meshStateController.add(RepositoryState.active);

      // Build metadata from current state
      final metadata = await _buildNodeMetadata();

      // Start Android Foreground Service (safe to call here as perms should be granted)
      await _wifiP2pSource.startMeshService();

      // DUAL-MODE: Start mesh node (advertising + discovery + server in one call)
      final success = await _wifiP2pSource.startMeshNode(
        nodeId: _nodeId!,
        metadata: metadata,
      );

      if (!success) {
        _meshStateController.add(RepositoryState.error);
        return Left(WifiP2pFailure('Failed to start mesh node'));
      }

      // Start stale node cleanup timer
      _staleCleanupTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _wifiP2pSource.cleanStaleNodes(),
      );

      return const Right(null);
    } catch (e) {
      _meshStateController.add(RepositoryState.error);
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  /// Stops mesh network operations.
  Future<void> stopMesh() async {
    _staleCleanupTimer?.cancel();
    _staleCleanupTimer = null;

    // DUAL-MODE: Stop mesh node (stops advertising, discovery, and server)
    await _wifiP2pSource.stopMeshNode();

    _meshStateController.add(RepositoryState.idle);
  }

  /// Starts discovery specifically.
  Future<void> startDiscovery() async {
    await _wifiP2pSource.startDiscovery();
  }

  /// Stops discovery specifically.
  Future<void> stopDiscovery() async {
    await _wifiP2pSource.stopDiscovery();
  }

  /// Alias for neighbors stream.
  Stream<List<NodeInfo>> get neighborsStream => neighbors;

  /// Alias for packets stream.
  Stream<ReceivedPacket> get packetsStream => _wifiP2pSource.receivedPackets;

  /// Gets the current list of neighbors.
  List<NodeInfo> getNeighbors() => currentNeighbors;

  /// Broadcasts updated metadata.
  Future<void> broadcastMetadata(Map<String, String> metadata) async {
    if (_nodeId != null) {
      await _wifiP2pSource.startBroadcasting(
        nodeId: _nodeId!,
        metadata: metadata,
      );
    }
  }

  /// Sends a generic packet (exposed for testing/debug).
  Future<bool> sendPacket(MeshPacket packet) async {
    // Add to outbox for persistence
    await _outbox.addPacket(packet);
    
    // Mark as seen
    _seenCache.markAsSeen(packet.id);
    
    // Attempt send
    return _forwardPacket(packet);
  }

  /// Sends an SOS alert through the mesh network.
  ///
  /// The SOS is:
  /// 1. Wrapped in a MeshPacket with high priority
  /// 2. Added to the outbox for persistence
  /// 3. Immediately attempted to send to the best neighbor
  Future<Either<Failure, String>> sendSos(dynamic sos) async {
    try {
      print('🚨 Repository: sendSos called');
      print('🚨 Repository: sos type is ${sos.runtimeType}');

      // FIX B-2: Mark this node as SOS sender so metadata advertises role='s'
      _currentRole = 's';
      // Re-broadcast metadata immediately so neighbors know we're a sender
      await updateMetadata();

      // Handle potential String/SosPayload confusion
      String payloadString;
      if (sos is String) {
        payloadString = sos;
      } else if (sos is SosPayload) {
        payloadString = sos.toJsonString();
      } else {
        payloadString = sos.toString();
      }

      // Create SOS packet with high priority
      final packet = MeshPacket.createSos(
        originatorId: _nodeId!,
        sosPayload: payloadString,
      );

      // Add to outbox for persistence
      print('🚨 Repository: Adding packet to outbox: ${packet.id}');
      await _outbox.addPacket(packet);

      // Mark as seen to prevent processing our own packet
      _seenCache.markAsSeen(packet.id);

      // Attempt immediate send
      print('🚨 Repository: Attempting immediate forward');
      final sendResult = await _forwardPacket(packet);

      if (sendResult) {
        print('🚨 Repository: Marked as sent in outbox');
        await _outbox.markSent(packet.id);
      } else {
        print('🚨 Repository: Forward failed (initial attempt)');
      }

      return Right(packet.id);
    } catch (e, stack) {
      print('🚨 Repository: Exception in sendSos: $e');
      print('🚨 Stack: $stack');
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  /// Processes an incoming packet from the network.
  ///
  /// 1. Checks if already seen (duplicate)
  /// 2. Validates with loop detector
  /// 3. If SOS, emits to SOS stream
  /// 4. If we have internet, delivers to server
  /// 5. Otherwise, forwards to next hop
  Future<void> _processIncomingPacket(ReceivedPacket received) async {
    try {
      // Deserialize packet
      final packet = MeshPacketModel.entityFromJsonString(received.packetJson);

      // Check if already seen (duplicate prevention)
      if (!_seenCache.checkAndMark(packet.id)) {
        // Already processed this packet
        return;
      }

      // Validate with loop detector
      final loopCheck = _loopDetector.shouldProcessPacket(
        packet: packet,
        currentNodeId: nodeId,
      );

      if (!loopCheck.isAllowed) {
        return;
      }

      // CRITICAL FIX: Force-refresh internet probe BEFORE deciding GOAL vs RELAY.
      // Declared at method scope so _handleForwardOrDeliver can reuse the result
      // (eliminates a redundant ~4s HTTP-timeout round on offline nodes).
      bool? freshConnectivity;

      // Process based on packet type
      if (packet.isSos) {
        print('🚨 Repository: Received SOS packet from ${received.senderIp}');
        freshConnectivity = await _internetProbe.checkConnectivity(forceRefresh: true);
        print('🚨 Repository: Real-time internet check → hasInternet=$freshConnectivity');

        // Emit SOS to the correct stream based on REAL internet status
        try {
          final sosPayload = SosPayload.fromJsonString(packet.payload);
          final receivedSos = ReceivedSos(
            packet: packet,
            sos: sosPayload,
            receivedAt: DateTime.now(),
            senderIp: received.senderIp,
          );

          if (freshConnectivity) {
            // Goal node: show in "I Can Help" responder UI
            _sosReceivedController.add(receivedSos);
            print('🚨 Repository: SOS emitted to GOAL stream (verified internet)');
          } else {
            // Relay node: emit to relay stream (shows in Relay Mode UI)
            _relayedSosController.add(receivedSos);
            print('🚨 Repository: SOS emitted to RELAY stream (no internet)');
          }
        } catch (e) {
          print('🚨 Repository: Failed to parse SOS payload: $e');
          // Invalid SOS payload, but still try to forward
        }
      }

      // Forward or deliver the packet.
      // For SOS: reuse the FRESH probe result (freshConnectivity != null).
      // For non-SOS (future): freshConnectivity is null → _handleForwardOrDeliver
      // does its own force-refresh.
      await _handleForwardOrDeliver(packet, received.senderIp, knownConnectivity: freshConnectivity);
    } catch (e) {
      // Log error but don't crash
    }
  }

  /// Handles forwarding or delivering a packet.
  ///
  /// FIX BUG-06: Incoming relay packets are now persisted to the outbox BEFORE
  /// attempting to forward. If _forwardPacket() fails (e.g., no neighbors),
  /// the packet remains in the outbox and the RelayOrchestrator will retry it
  /// on its next 10-second cycle. Previously, a single Wi-Fi scan gap meant
  /// permanent packet loss for transit packets.
  ///
  /// CRITICAL FIX (double-hop): Store the ORIGINAL packet (without this node's
  /// hop) in the outbox.  The hop is appended only at actual send time so that
  /// both the immediate-forward path and every orchestrator retry add exactly
  /// one hop, not two.
  /// [knownConnectivity] — when provided by the caller (e.g., _processIncomingPacket
  /// already did a force-refresh), we reuse that result instead of probing again.
  /// This eliminates a redundant ~4 s HTTP-timeout round on offline nodes.
  Future<void> _handleForwardOrDeliver(
    MeshPacket packet,
    String senderIp, {
    bool? knownConnectivity,
  }) async {
    // If packet is expired, don't forward
    if (!packet.isAlive) {
      print('⏰ Packet ${packet.id} expired (TTL exhausted), dropping');
      return;
    }

    // Use the already-verified result when available; otherwise force-refresh.
    final hasInternetNow = knownConnectivity ??
        await _internetProbe.checkConnectivity(forceRefresh: true);

    _relayDiagController.add(RelayDiagnostic(
      packetId: packet.id,
      stage: 'handleForwardOrDeliver',
      detail: 'hasInternet=$hasInternetNow, isSos=${packet.isSos}, hop=${packet.hopCount}',
    ));

    if (hasInternetNow && packet.isSos) {
      // ✅ This node has VERIFIED real internet — it IS the Goal node.
      // The SOS was already emitted to the Goal stream (I Can Help UI) in
      // _processIncomingPacket. Our job here is to STOP forwarding so the
      // packet doesn't continue bouncing through the mesh.
      //
      // Goal node reached — upload SOS to AWS cloud via CloudClient.
      print('✅ Goal node reached — SOS ${packet.id} delivered to device with real internet. Uploading to cloud...');
      _relayDiagController.add(RelayDiagnostic(
        packetId: packet.id,
        stage: 'goalReached',
        detail: 'Delivered to goal node with internet — triggering cloud upload',
      ));

      // Persist the SOS packet in the outbox so CloudClient can pick it up.
      // CloudClient reads the outbox for SOS packets not yet uploaded.
      await _outbox.addPacket(packet);
      _seenCache.markAsSeen(packet.id);

      // Trigger immediate cloud sync (non-blocking — runs in background).
      _cloudClient?.syncPendingPackets().then((count) {
        if (count > 0) {
          print('☁️ CloudClient: $count SOS packet(s) uploaded to AWS');
        }
      }).catchError((e) {
        print('☁️ CloudClient: Upload failed — will retry on next cycle: $e');
      });
      return;
    }

    // FIX BUG-06 + double-hop fix:
    // Persist the ORIGINAL packet (no hop added yet) to outbox so that the
    // RelayOrchestrator retry path adds exactly one hop via _attemptSend.
    // The immediate-forward path below also adds one hop via _forwardPacket.
    print('📦 Persisting relay packet ${packet.id} to outbox before forward attempt');
    await _outbox.addPacket(packet);

    // Mark as seen to prevent re-processing our own forwarded packet
    _seenCache.markAsSeen(packet.id);

    // Add hop NOW only for the immediate send attempt
    final hopAddedPacket = packet.addHop(nodeId);

    // Attempt immediate forward
    final forwarded = await _forwardPacket(hopAddedPacket);
    
    if (forwarded) {
      // Forward succeeded — mark as sent in outbox so orchestrator skips it
      print('✅ Relay packet ${packet.id} forwarded immediately, marking sent');
      await _outbox.markSent(packet.id);
      _immediateForwardController.add(packet.id);
      _relayDiagController.add(RelayDiagnostic(
        packetId: packet.id,
        stage: 'immediateForwardSuccess',
        detail: 'Forwarded immediately, marked sent in outbox',
      ));
    } else {
      // Forward failed — packet stays in outbox. RelayOrchestrator will pick it up
      // on the next 10-second cycle when neighbors become available.
      print('⏳ Relay packet ${packet.id} forward failed — queued for retry in outbox');
      _relayDiagController.add(RelayDiagnostic(
        packetId: packet.id,
        stage: 'immediateForwardFailed',
        detail: 'Queued for retry via orchestrator',
      ));
    }
  }

  /// Forwards a packet to the best available neighbor using connect-and-send.
  Future<bool> _forwardPacket(MeshPacket packet) async {
    // Get current neighbors
    final neighbors = currentNeighbors;

    print('🚨 _forwardPacket: Checking neighbors (count: ${neighbors.length})');
    if (neighbors.isNotEmpty) {
      print('🚨 Neighbors: ${neighbors.map((n) => n.deviceAddress).toList()}');
    }

    if (neighbors.isEmpty) {
      // No neighbors, keep in outbox for later
      print('❌ No neighbors available for forwarding');
      _relayDiagController.add(RelayDiagnostic(
        packetId: packet.id,
        stage: 'forwardPacket',
        detail: 'No neighbors available',
      ));
      return false;
    }

    // Use AI router to find best candidate
    final bestNode = _aiRouter.selectBestNode(
      neighbors: neighbors,
      packet: packet,
      currentNodeId: nodeId,
    );

    if (bestNode == null) {
      // No viable route
      print('❌ No viable route found by AI router');
      _relayDiagController.add(RelayDiagnostic(
        packetId: packet.id,
        stage: 'forwardPacket',
        detail: 'AI router returned no viable route (${neighbors.length} neighbors checked)',
      ));
      return false;
    }

    print('📡 Forwarding packet to ${bestNode.id} (${bestNode.deviceAddress})');

    // DUAL-MODE: Use connect-and-send flow
    // This connects to the device, sends the packet, and disconnects
    print('🚨 Calling wifiP2pSource.connectAndSendPacket...');
    final result = await _wifiP2pSource.connectAndSendPacket(
      deviceAddress: bestNode.deviceAddress,
      packetJson: MeshPacketModel.entityToJsonString(packet),
    );

    if (result.success) {
      print('✅ Packet forwarded successfully to ${bestNode.id}');
      _relayDiagController.add(RelayDiagnostic(
        packetId: packet.id,
        stage: 'forwardSuccess',
        detail: 'Sent to ${bestNode.id} (${bestNode.deviceAddress})',
      ));
      return true;
    } else {
      print('❌ Forward failed: ${result.error} - ${result.message}');
      _relayDiagController.add(RelayDiagnostic(
        packetId: packet.id,
        stage: 'forwardFailed',
        detail: 'Target=${bestNode.id}, error=${result.error}, msg=${result.message}',
      ));
      return false;
    }
  }

  /// Builds metadata map for broadcasting.
  Future<Map<String, String>> _buildNodeMetadata() async {
    final location = _locationManager.lastKnownLocation;
    final batteryLevel = await _battery.batteryLevel;
    // FIX Internet-Probe False-Positive: Force-refresh probe so metadata
    // always reflects true connectivity, not stale cache.
    final hasInternet = await _internetProbe.checkConnectivity(forceRefresh: true);
    // FIX B-7: Read real RSSI from native Wi-Fi interface
    final rssi = await _wifiP2pSource.getSignalStrength();
    
    return {
      'id': _nodeId!,
      'bat': batteryLevel.toString(),
      'net': hasInternet ? '1' : '0',
      'lat': location?.latitude.toStringAsFixed(6) ?? '0.0',
      'lng': location?.longitude.toStringAsFixed(6) ?? '0.0',
      'sig': rssi.toString(),
      'tri': 'n',  // no triage
      // FIX B-2: Priority: goal (internet) > sender (SOS) > relay
      'rol': hasInternet ? 'g' : _currentRole,
      'rel': batteryLevel > 15 ? '1' : '0',  // available for relay if battery > 15%
    };
  }

  /// Sets up event listeners for streams.
  void _setupEventListeners() {
    // Listen to discovered nodes
    _nodeSubscription = _wifiP2pSource.discoveredNodes.listen((nodes) {
      _neighborController.add(nodes);
    });

    // Listen to received packets
    _packetSubscription = _wifiP2pSource.receivedPackets.listen((received) {
      _processIncomingPacket(received);
    });
  }

  /// Updates broadcast metadata (e.g., when location changes).
  Future<void> updateMetadata() async {
    if (_nodeId == null) return;

    final metadata = await _buildNodeMetadata();
    await _wifiP2pSource.startBroadcasting(
      nodeId: _nodeId!,
      metadata: metadata,
    );
  }

  /// Gets outbox statistics.
  OutboxStats getOutboxStats() {
    return _outbox.getStats();
  }

  /// Gets pending packets from outbox.
  List<MeshPacket> getPendingPackets() {
    return _outbox.getPendingPackets();
  }

  /// Disposes of all resources.
  Future<void> dispose() async {
    _staleCleanupTimer?.cancel();
    await _packetSubscription?.cancel();
    await _nodeSubscription?.cancel();
    
    await _outbox.close();
    await _wifiP2pSource.cleanup();
    _locationManager.dispose();

    await _meshStateController.close();
    await _sosReceivedController.close();
    await _relayedSosController.close();
    await _immediateForwardController.close();
    await _neighborController.close();
    await _relayDiagController.close();
  }
}

/// Current state of the mesh network repository.
enum RepositoryState {
  idle,
  initializing,
  ready,
  active,
  error,
}

/// A received SOS alert.
class ReceivedSos {
  final MeshPacket packet;
  final SosPayload sos;
  final DateTime receivedAt;
  final String senderIp;

  ReceivedSos({
    required this.packet,
    required this.sos,
    required this.receivedAt,
    required this.senderIp,
  });
}

/// Failure types for mesh operations.
abstract class Failure {
  final String message;
  const Failure(this.message);
}

class WifiP2pFailure extends Failure {
  const WifiP2pFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message);
}

/// Diagnostic event emitted during relay forwarding decisions.
class RelayDiagnostic {
  final String packetId;
  final String stage;
  final String detail;
  final DateTime timestamp;

  RelayDiagnostic({
    required this.packetId,
    required this.stage,
    required this.detail,
  }) : timestamp = DateTime.now();

  @override
  String toString() => '[$stage] pkt=$packetId | $detail @ $timestamp';
}
