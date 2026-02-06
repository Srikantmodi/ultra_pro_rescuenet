import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/mesh_repository_impl.dart';
import '../../../data/services/internet_probe.dart';
import '../../../data/services/relay_orchestrator.dart';
import '../../../domain/entities/mesh_packet.dart';
import '../../../domain/entities/node_info.dart';
import 'mesh_event.dart';
import 'mesh_state.dart';

import '../../../../../core/platform/device_info_provider.dart';

/// BLoC for managing mesh network state.
class MeshBloc extends Bloc<MeshEvent, MeshState> {
  final MeshRepositoryImpl _repository;
  final RelayOrchestrator _relayOrchestrator;
  final InternetProbe _internetProbe;

  StreamSubscription? _neighborsSubscription;
  StreamSubscription? _packetsSubscription;

  MeshBloc({
    required MeshRepositoryImpl repository,
    required RelayOrchestrator relayOrchestrator,
    required InternetProbe internetProbe,
  })  : _repository = repository,
        _relayOrchestrator = relayOrchestrator,
        _internetProbe = internetProbe,
        super(const MeshState()) {
    on<InitializeMesh>(_onInitialize);
    on<StartMesh>(_onStart);
    on<StopMesh>(_onStop);
    on<SendSos>(_onSendSos);
    on<UpdateBattery>(_onUpdateBattery);
    on<UpdateLocation>(_onUpdateLocation);
    on<ToggleRelayMode>(_onToggleRelay);
    on<NeighborsUpdated>(_onNeighborsUpdated);
    on<ConnectivityChanged>(_onConnectivityChanged);
    on<PacketReceived>(_onPacketReceived);
  }

  StreamSubscription? _connectivitySubscription;

  Future<void> _onInitialize(
    InitializeMesh event,
    Emitter<MeshState> emit,
  ) async {
    emit(state.copyWith(status: MeshStatus.initializing));

    try {
      // Use persistent Device ID
      final nodeId = await DeviceInfoProvider.getDeviceId();
      await _repository.initialize(nodeId: nodeId);

      final hasInternet = await _internetProbe.checkConnectivity();
      final currentNode = NodeInfo(
        id: nodeId,
        deviceAddress: '',
        displayName: 'My Device',
        batteryLevel: 100,
        hasInternet: hasInternet,
        latitude: 0,
        longitude: 0,
        lastSeen: DateTime.now(),
        signalStrength: -50,
        triageLevel: NodeInfo.triageNone,
        role: NodeInfo.roleIdle,
        isAvailableForRelay: true,
      );

      emit(state.copyWith(
        status: MeshStatus.inactive,
        currentNode: currentNode,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: MeshStatus.error,
        error: e.toString(),
      ));
    }
  }

  Future<void> _onStart(
    StartMesh event,
    Emitter<MeshState> emit,
  ) async {
    try {
      // Start full mesh operation: service registration + discovery + server
      final result = await _repository.startMesh();
      if (result.isLeft()) {
        final failure = result.fold((l) => l, (r) => null);
        emit(state.copyWith(
          status: MeshStatus.error,
          error: failure?.message ?? 'Failed to start mesh node',
        ));
        return;
      }

      _relayOrchestrator.start();
      _internetProbe.startProbing();

      _neighborsSubscription?.cancel();
      _neighborsSubscription = _repository.neighborsStream.listen(
        (neighbors) => add(NeighborsUpdated(neighbors)),
      );

      _connectivitySubscription?.cancel();
      _connectivitySubscription = _internetProbe.connectivityStream.listen(
        (hasInternet) => add(ConnectivityChanged(hasInternet)),
      );

      _packetsSubscription?.cancel();
      _packetsSubscription = _repository.packetsStream.listen(
        (receivedPacket) {
          try {
            final map = jsonDecode(receivedPacket.packetJson) as Map<String, dynamic>;
            final packet = MeshPacket.fromJson(map);
            add(PacketReceived(packet));
          } catch (e) {
            // Ignore parse errors
          }
        },
      );

      emit(state.copyWith(
        status: MeshStatus.active,
        isRelaying: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: MeshStatus.error,
        error: e.toString(),
      ));
    }
  }

  Future<void> _onStop(
    StopMesh event,
    Emitter<MeshState> emit,
  ) async {
    await _neighborsSubscription?.cancel();
    await _packetsSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    _relayOrchestrator.stop();
    _internetProbe.stopProbing();

    try {
      await _repository.stopMesh();
    } catch (e) {
      // Ignore
    }

    emit(state.copyWith(
      status: MeshStatus.inactive,
      isRelaying: false,
    ));
  }

  Future<void> _onConnectivityChanged(
    ConnectivityChanged event,
    Emitter<MeshState> emit,
  ) async {
    if (state.currentNode != null) {
       final updated = state.currentNode!.copyWith(
         hasInternet: event.hasInternet,
       );
       emit(state.copyWith(currentNode: updated));
       await _repository.broadcastMetadata(updated.toTxtRecord());
    }
  }


  Future<void> _onSendSos(
    SendSos event,
    Emitter<MeshState> emit,
  ) async {
    try {
      await _repository.sendSos(event.payload);

      emit(state.copyWith(
        statistics: state.statistics.copyWith(
          packetsSent: state.statistics.packetsSent + 1,
        ),
      ));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to send SOS: $e'));
    }
  }

  Future<void> _onUpdateBattery(
    UpdateBattery event,
    Emitter<MeshState> emit,
  ) async {
    if (state.currentNode != null) {
      final updated = state.currentNode!.copyWith(
        batteryLevel: event.level,
      );
      emit(state.copyWith(currentNode: updated));
      await _repository.broadcastMetadata(updated.toTxtRecord());
    }
  }

  Future<void> _onUpdateLocation(
    UpdateLocation event,
    Emitter<MeshState> emit,
  ) async {
    if (state.currentNode != null) {
      final updated = state.currentNode!.copyWith(
        latitude: event.latitude,
        longitude: event.longitude,
      );
      emit(state.copyWith(currentNode: updated));
      await _repository.broadcastMetadata(updated.toTxtRecord());
    }
  }

  Future<void> _onToggleRelay(
    ToggleRelayMode event,
    Emitter<MeshState> emit,
  ) async {
    if (event.enabled) {
      _relayOrchestrator.start();
    } else {
      _relayOrchestrator.stop();
    }
    emit(state.copyWith(isRelaying: event.enabled));
  }

  void _onNeighborsUpdated(
    NeighborsUpdated event,
    Emitter<MeshState> emit,
  ) {
    emit(state.copyWith(neighbors: event.neighbors));
  }

  void _onPacketReceived(
    PacketReceived event,
    Emitter<MeshState> emit,
  ) {
    final packet = event.packet;
    final updatedPackets = [packet, ...state.recentPackets].take(50).toList();

    if (packet.type == PacketType.sos) {
      final updatedSos = [packet, ...state.sosAlerts].take(20).toList();
      emit(state.copyWith(
        recentPackets: updatedPackets,
        sosAlerts: updatedSos,
        statistics: state.statistics.copyWith(
          packetsReceived: state.statistics.packetsReceived + 1,
          sosReceived: state.statistics.sosReceived + 1,
        ),
      ));
    } else {
      emit(state.copyWith(
        recentPackets: updatedPackets,
        statistics: state.statistics.copyWith(
          packetsReceived: state.statistics.packetsReceived + 1,
        ),
      ));
    }
  }

  @override
  Future<void> close() {
    _neighborsSubscription?.cancel();
    _packetsSubscription?.cancel();
    return super.close();
  }
}
