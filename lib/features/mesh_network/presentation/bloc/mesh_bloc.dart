import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/platform/device_info_provider.dart';
import '../../domain/entities/mesh_packet.dart';
import '../../domain/entities/node_info.dart';
import '../../domain/entities/sos_payload.dart';
import '../../data/repositories/mesh_repository_impl.dart';
import '../../data/services/relay_orchestrator.dart';
import '../../data/services/internet_probe.dart';

// ============== EVENTS ==============

abstract class MeshEvent extends Equatable {
  const MeshEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize the mesh network system.
class MeshInitialize extends MeshEvent {
  const MeshInitialize();
}

/// Start mesh network operations (broadcasting, discovery, server).
class MeshStart extends MeshEvent {
  const MeshStart();
}

/// Stop mesh network operations.
class MeshStop extends MeshEvent {
  const MeshStop();
}

/// Send an SOS alert.
class MeshSendSos extends MeshEvent {
  final SosPayload sos;

  const MeshSendSos(this.sos);

  @override
  List<Object?> get props => [sos];
}

/// Cancel an active SOS alert.
class MeshCancelSos extends MeshEvent {
  final String sosId;

  const MeshCancelSos(this.sosId);

  @override
  List<Object?> get props => [sosId];
}

/// Force a relay attempt for pending packets.
class MeshForceRelay extends MeshEvent {
  const MeshForceRelay();
}

/// Update broadcast metadata (e.g., after location change).
class MeshUpdateMetadata extends MeshEvent {
  const MeshUpdateMetadata();
}

/// Internal: Neighbors list updated.
class _NeighborsUpdated extends MeshEvent {
  final List<NodeInfo> neighbors;

  const _NeighborsUpdated(this.neighbors);

  @override
  List<Object?> get props => [neighbors];
}

/// Internal: SOS received from network.
class _SosReceived extends MeshEvent {
  final ReceivedSos sos;

  const _SosReceived(this.sos);

  @override
  List<Object?> get props => [sos];
}

/// Internal: SOS relayed through this node (no internet).
class _RelayedSosReceived extends MeshEvent {
  final ReceivedSos sos;

  const _RelayedSosReceived(this.sos);

  @override
  List<Object?> get props => [sos];
}

/// Internal: Relay stats updated.
class _RelayStatsUpdated extends MeshEvent {
  final RelayStats stats;

  const _RelayStatsUpdated(this.stats);

  @override
  List<Object?> get props => [stats];
}

/// Internal: Connectivity changed.
class _ConnectivityChanged extends MeshEvent {
  final bool hasInternet;

  const _ConnectivityChanged(this.hasInternet);

  @override
  List<Object?> get props => [hasInternet];
}

// ============== STATES ==============

abstract class MeshState extends Equatable {
  const MeshState();

  String? get nodeId => null;

  @override
  List<Object?> get props => [];
}

/// Initial state before initialization.
class MeshInitial extends MeshState {
  const MeshInitial();
}

/// Loading/initializing state.
class MeshLoading extends MeshState {
  final String message;

  const MeshLoading({this.message = 'Initializing...'});

  @override
  List<Object?> get props => [message];
}

/// Error state.
class MeshError extends MeshState {
  final String message;

  const MeshError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Ready state - initialized but not active.
class MeshReady extends MeshState {
  @override
  final String? nodeId;
  
  const MeshReady({this.nodeId});
  
  @override
  List<Object?> get props => [nodeId];
}

/// Active state - mesh network is running.
class MeshActive extends MeshState {
  @override
  final String nodeId;
  final List<NodeInfo> neighbors;
  final bool hasInternet;
  final RelayStats relayStats;
  final List<ReceivedSos> recentSosAlerts;
  final String? activeSosId;
  final bool isRelaying;
  final int relayedSosCount;

  /// FIX BUG-R1: Pre-filtered list of neighbors eligible as forward targets.
  /// Excludes SOS originators, nodes in packet traces, and sender-role nodes.
  /// The relay_mode_page uses this instead of raw [neighbors] to avoid
  /// displaying the SOS sender as a forward target (routing loop visual).
  final List<NodeInfo> forwardTargets;

  const MeshActive({
    required this.nodeId,
    this.neighbors = const [],
    this.hasInternet = false,
    this.relayStats = const RelayStats(
      packetsSent: 0,
      packetsFailed: 0,
      permanentDrops: 0,
      pendingCount: 0,
      neighborsCount: 0,
      isRunning: false,
      consecutiveFailures: 0,
    ),
    this.recentSosAlerts = const [],
    this.activeSosId,
    this.isRelaying = false,
    this.relayedSosCount = 0,
    this.forwardTargets = const [],
  });

  MeshActive copyWith({
    String? nodeId,
    List<NodeInfo>? neighbors,
    bool? hasInternet,
    RelayStats? relayStats,
    List<ReceivedSos>? recentSosAlerts,
    String? activeSosId,
    bool? isRelaying,
    int? relayedSosCount,
    List<NodeInfo>? forwardTargets,
  }) {
    return MeshActive(
      nodeId: nodeId ?? this.nodeId,
      neighbors: neighbors ?? this.neighbors,
      hasInternet: hasInternet ?? this.hasInternet,
      relayStats: relayStats ?? this.relayStats,
      recentSosAlerts: recentSosAlerts ?? this.recentSosAlerts,
      activeSosId: activeSosId,
      isRelaying: isRelaying ?? this.isRelaying,
      relayedSosCount: relayedSosCount ?? this.relayedSosCount,
      forwardTargets: forwardTargets ?? this.forwardTargets,
    );
  }

  @override
  List<Object?> get props => [
        nodeId,
        neighbors,
        hasInternet,
        relayStats,
        recentSosAlerts,
        activeSosId,
        isRelaying,
        relayedSosCount,
        forwardTargets,
      ];

  /// Number of neighbors currently available.
  int get neighborCount => neighbors.length;

  /// Whether we have any neighbors.
  bool get hasNeighbors => neighbors.isNotEmpty;

  /// Best neighbor for routing (if any).
  NodeInfo? get bestNeighbor => neighbors.isNotEmpty ? neighbors.first : null;

  /// Whether an SOS is currently active.
  bool get hasSosActive => activeSosId != null;
}

// ============== BLOC ==============

/// BLoC for managing mesh network state and operations.
///
/// This is the main state management component for the mesh network UI.
/// It orchestrates:
/// - Initialization and lifecycle of mesh network
/// - SOS sending and receiving
/// - Neighbor discovery updates
/// - Relay statistics
/// - Connectivity status
class MeshBloc extends Bloc<MeshEvent, MeshState> {
  final MeshRepositoryImpl _repository;
  final RelayOrchestrator _relayOrchestrator;
  final InternetProbe _internetProbe;

  // Subscriptions
  StreamSubscription? _neighborsSubscription;
  StreamSubscription? _sosSubscription;
  StreamSubscription? _relayedSosSubscription;
  StreamSubscription? _immediateForwardSubscription;
  StreamSubscription? _relayStatsSubscription;
  StreamSubscription? _connectivitySubscription;

  // Recent SOS alerts (keep last 10)
  final List<ReceivedSos> _recentSosAlerts = [];
  static const int _maxRecentAlerts = 10;

  /// Creates the MeshBloc with required dependencies.
  MeshBloc({
    required MeshRepositoryImpl repository,
    required RelayOrchestrator relayOrchestrator,
    required InternetProbe internetProbe,
  })  : _repository = repository,
        _relayOrchestrator = relayOrchestrator,
        _internetProbe = internetProbe,
        super(const MeshInitial()) {
    // Register event handlers
    on<MeshInitialize>(_onInitialize);
    on<MeshStart>(_onStart);
    on<MeshStop>(_onStop);
    on<MeshSendSos>(_onSendSos);
    on<MeshCancelSos>(_onCancelSos);
    on<MeshForceRelay>(_onForceRelay);
    on<MeshUpdateMetadata>(_onUpdateMetadata);
    on<_NeighborsUpdated>(_onNeighborsUpdated);
    on<_SosReceived>(_onSosReceived);
    on<_RelayedSosReceived>(_onRelayedSosReceived);
    on<_RelayStatsUpdated>(_onRelayStatsUpdated);
    on<_ConnectivityChanged>(_onConnectivityChanged);
  }

  /// Handles initialization.
  Future<void> _onInitialize(
    MeshInitialize event,
    Emitter<MeshState> emit,
  ) async {
    emit(const MeshLoading(message: 'Initializing mesh network...'));

    // FIX BUG-11: Use persistent device ID instead of random UUID.
    // The old code generated a new UUID on every restart, meaning relay nodes
    // could never recognise a previously-seen device. DeviceInfoProvider stores
    // the ID in Hive so it survives restarts.
    final nodeId = await DeviceInfoProvider.getDeviceId();

    // Wire the node ID into the relay orchestrator
    _relayOrchestrator.setNodeId(nodeId);

    // Wire local delivery callback so the orchestrator can deliver SOS locally
    // when this node gains internet while packets are still in the outbox.
    _relayOrchestrator.onLocalDelivery = _repository.tryDeliverLocally;

    // Initialize repository
    final result = await _repository.initialize(nodeId: nodeId);

    result.fold(
      (failure) => emit(MeshError(failure.message)),
      (_) {
        // Set up subscriptions
        _setupSubscriptions();

        // Start internet probing
        _internetProbe.startProbing();

        emit(MeshReady(nodeId: _repository.nodeId));
      },
    );
  }

  /// Handles starting mesh operations.
  Future<void> _onStart(
    MeshStart event,
    Emitter<MeshState> emit,
  ) async {
    emit(const MeshLoading(message: 'Starting mesh network...'));

    final result = await _repository.startMesh();

    result.fold(
      (failure) => emit(MeshError(failure.message)),
      (_) {
        // Start relay orchestrator
        _relayOrchestrator.start();

        emit(MeshActive(
          nodeId: _repository.nodeId,
          hasInternet: _internetProbe.hasInternet,
          isRelaying: true,
        ));
      },
    );
  }

  /// Handles stopping mesh operations.
  Future<void> _onStop(
    MeshStop event,
    Emitter<MeshState> emit,
  ) async {
    _relayOrchestrator.stop();
    await _repository.stopMesh();
    emit(MeshReady(nodeId: _repository.nodeId));
  }

  /// Handles sending an SOS.
  ///
  /// FIX BUG-02: Previously, if state was not MeshActive, the SOS was silently
  /// dropped. Survivors never open Relay Mode, so they stay in MeshReady forever.
  /// Now we auto-start the mesh if the state is MeshReady, then proceed with send.
  Future<void> _onSendSos(
    MeshSendSos event,
    Emitter<MeshState> emit,
  ) async {
    print('🚨 MeshBloc: _onSendSos triggered');
    final currentState = state;
    print('🚨 MeshBloc: Current state is ${currentState.runtimeType}');
    
    // FIX BUG-02: Auto-start mesh if in MeshReady state (survivor path)
    if (currentState is MeshReady) {
      print('🚨 MeshBloc: State is MeshReady — auto-starting mesh for SOS sender...');
      emit(const MeshLoading(message: 'Starting mesh for SOS...'));
      
      final startResult = await _repository.startMesh();
      
      final startFailed = startResult.fold(
        (failure) {
          print('🚨 MeshBloc: Auto-start mesh failed: ${failure.message}');
          emit(MeshError('Failed to start mesh: ${failure.message}'));
          return true;
        },
        (_) => false,
      );
      
      if (startFailed) return;
      
      // Start relay orchestrator
      _relayOrchestrator.start();
      
      // Emit MeshActive, then proceed to send
      final activeState = MeshActive(
        nodeId: _repository.nodeId,
        hasInternet: _internetProbe.hasInternet,
        isRelaying: true,
      );
      emit(activeState);
      
      print('🚨 MeshBloc: Auto-started mesh, now sending SOS...');
      
      // Now send from the active state
      final result = await _repository.sendSos(event.sos);
      result.fold(
        (failure) {
          print('🚨 MeshBloc: Failed to send SOS: ${failure.message}');
        },
        (sosId) {
          print('🚨 MeshBloc: SOS sent successfully, ID: $sosId');
          emit(activeState.copyWith(activeSosId: sosId));
        },
      );
      return;
    }
    
    if (currentState is! MeshActive) {
      print('🚨 MeshBloc: State is ${currentState.runtimeType} — cannot send SOS (not Ready or Active)');
      return;
    }

    print('🚨 MeshBloc: Calling repository.sendSos');
    final result = await _repository.sendSos(event.sos);

    result.fold(
      (failure) {
        print('🚨 MeshBloc: Failed to send SOS: ${failure.message}');
        // TODO: Show error to user
      },
      (sosId) {
        print('🚨 MeshBloc: SOS sent successfully, ID: $sosId');
        emit(currentState.copyWith(activeSosId: sosId));
      },
    );
  }

  /// Handles cancelling an SOS.
  void _onCancelSos(
    MeshCancelSos event,
    Emitter<MeshState> emit,
  ) {
    final currentState = state;
    if (currentState is! MeshActive) return;

    // TODO: Implement SOS cancellation packet
    emit(currentState.copyWith(activeSosId: null));
  }

  /// Handles force relay attempt.
  Future<void> _onForceRelay(
    MeshForceRelay event,
    Emitter<MeshState> emit,
  ) async {
    await _relayOrchestrator.forceRelay();
  }

  /// Handles metadata update.
  Future<void> _onUpdateMetadata(
    MeshUpdateMetadata event,
    Emitter<MeshState> emit,
  ) async {
    await _repository.updateMetadata();
  }

  /// Handles neighbors list update.
  void _onNeighborsUpdated(
    _NeighborsUpdated event,
    Emitter<MeshState> emit,
  ) {
    final currentState = state;
    if (currentState is MeshActive) {
      final targets = _computeForwardTargets(event.neighbors);
      emit(currentState.copyWith(
        neighbors: event.neighbors,
        forwardTargets: targets,
      ));
    }
  }

  /// Handles received SOS.
  void _onSosReceived(
    _SosReceived event,
    Emitter<MeshState> emit,
  ) {
    final currentState = state;
    if (currentState is! MeshActive) return;

    // Add to recent alerts
    _recentSosAlerts.insert(0, event.sos);
    if (_recentSosAlerts.length > _maxRecentAlerts) {
      _recentSosAlerts.removeLast();
    }

    emit(currentState.copyWith(
      recentSosAlerts: List.from(_recentSosAlerts),
    ));
  }

  /// Handles SOS that was received and relayed (not for local display as responder).
  ///
  /// FIX BUG-R1: Also recompute forward targets because a new SOS packet in the
  /// outbox means the originator must be excluded from the UI target list.
  void _onRelayedSosReceived(
    _RelayedSosReceived event,
    Emitter<MeshState> emit,
  ) {
    final currentState = state;
    if (currentState is! MeshActive) return;

    final targets = _computeForwardTargets(currentState.neighbors);
    emit(currentState.copyWith(
      relayedSosCount: currentState.relayedSosCount + 1,
      forwardTargets: targets,
    ));
  }

  /// Handles relay stats update.
  ///
  /// FIX BUG-R1: Recompute forward targets because a completed send may have
  /// removed a packet from the outbox, changing which nodes are excluded.
  void _onRelayStatsUpdated(
    _RelayStatsUpdated event,
    Emitter<MeshState> emit,
  ) {
    final currentState = state;
    if (currentState is MeshActive) {
      final targets = _computeForwardTargets(currentState.neighbors);
      emit(currentState.copyWith(
        relayStats: event.stats,
        forwardTargets: targets,
      ));
    }
  }

  /// Handles connectivity change.
  ///
  /// FIX BUG-03 + BUG-08: When connectivity changes, we MUST re-broadcast our
  /// metadata so other nodes learn our updated internet status. Without this,
  /// a node that gains internet (becoming a Goal Node) never propagates its
  /// `net=1` / `rol=g` values — other relay nodes keep routing with the old
  /// `net=0` value and the Goal Node is never selected for delivery.
  ///
  /// FIX: Internet Probe False-Positive — When connectivity transitions from
  /// true → false (node loses internet), clear all stale "I Can Help" SOS
  /// alerts. These alerts were routed to the GOAL stream when the node thought
  /// it had internet. Now that it doesn't, they're invalid — this node can't
  /// actually deliver them to the cloud.
  Future<void> _onConnectivityChanged(
    _ConnectivityChanged event,
    Emitter<MeshState> emit,
  ) async {
    final currentState = state;
    if (currentState is MeshActive) {
      // Detect goal → relay transition (lost internet)
      if (currentState.hasInternet && !event.hasInternet) {
        print('⚠️ MeshBloc: Internet LOST — clearing ${_recentSosAlerts.length} stale goal-stream SOS alerts');
        _recentSosAlerts.clear();
        emit(currentState.copyWith(
          hasInternet: false,
          recentSosAlerts: const [],
        ));
      } else {
        emit(currentState.copyWith(hasInternet: event.hasInternet));
      }
      
      // FIX BUG-03: Trigger metadata re-broadcast to propagate new internet status
      print('🌐 MeshBloc: Connectivity changed → hasInternet=${event.hasInternet} — updating metadata');
      await _repository.updateMetadata();
    }
  }

  /// FIX BUG-R1 + BUG-R3: Computes the filtered list of neighbors eligible as
  /// forward targets. This mirrors the AI Router's filtering logic so the UI
  /// stays consistent with actual routing decisions.
  ///
  /// Exclusion rules:
  /// 1. Nodes whose role is 'sender' (they are SOS originators, not relay targets)
  /// 2. Nodes whose ID matches the originatorId of any pending outbox packet
  /// 3. Nodes whose ID appears in the trace of any pending outbox packet
  /// 4. Stale nodes (not seen within the stale timeout window)
  /// 5. Nodes not available for relay (isAvailableForRelay == false)
  List<NodeInfo> _computeForwardTargets(List<NodeInfo> neighbors) {
    final List<MeshPacket> pendingPackets = _repository.getPendingPackets();

    // Collect all IDs that should be excluded
    final excludedIds = <String>{};

    for (final packet in pendingPackets) {
      // Exclude the originator of each packet
      excludedIds.add(packet.originatorId);
      // Exclude every node already in the packet's trace
      excludedIds.addAll(packet.trace);
    }

    return neighbors.where((node) {
      // Rule 1: Exclude sender-role nodes (they are SOS originators)
      if (node.role == NodeInfo.roleSender) {
        return false;
      }

      // Rule 2+3: Exclude originators and nodes in packet traces
      if (excludedIds.contains(node.id)) {
        return false;
      }

      // Rule 4 (BUG-R3): Exclude stale nodes — they haven't been seen
      // recently and likely moved out of range or turned off.
      if (node.isStale) {
        return false;
      }

      // Rule 5 (BUG-R3): Exclude nodes explicitly marked unavailable.
      if (!node.isAvailableForRelay) {
        return false;
      }

      return true;
    }).toList();
  }

  /// Sets up stream subscriptions.
  void _setupSubscriptions() {
    _neighborsSubscription = _repository.neighbors.listen((neighbors) {
      add(_NeighborsUpdated(neighbors));
    });

    _sosSubscription = _repository.sosAlerts.listen((sos) {
      add(_SosReceived(sos));
    });

    _relayedSosSubscription = _repository.relayedSosAlerts.listen((sos) {
      add(_RelayedSosReceived(sos));
    });

    _immediateForwardSubscription = _repository.immediateForwards.listen((_) {
      _relayOrchestrator.recordExternalForward();
    });

    _relayStatsSubscription = _relayOrchestrator.stats.listen((stats) {
      add(_RelayStatsUpdated(stats));
    });

    _connectivitySubscription = _internetProbe.connectivityStream.listen((hasInternet) {
      add(_ConnectivityChanged(hasInternet));
    });
  }

  @override
  Future<void> close() async {
    await _neighborsSubscription?.cancel();
    await _sosSubscription?.cancel();
    await _relayedSosSubscription?.cancel();
    await _immediateForwardSubscription?.cancel();
    await _relayStatsSubscription?.cancel();
    await _connectivitySubscription?.cancel();

    _relayOrchestrator.dispose();
    _internetProbe.dispose();
    await _repository.dispose();

    return super.close();
  }
}
