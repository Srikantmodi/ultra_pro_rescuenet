import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/datasources/remote/wifi_p2p_source.dart';
import '../../../domain/entities/node_info.dart';
import 'discovery_event.dart';
import 'discovery_state.dart';

/// BLoC for managing discovery state.
class DiscoveryBloc extends Bloc<DiscoveryEvent, DiscoveryState> {
  final WifiP2pSource _wifiP2pSource;
  StreamSubscription? _neighborsSubscription;

  DiscoveryBloc({required WifiP2pSource wifiP2pSource})
      : _wifiP2pSource = wifiP2pSource,
        super(const DiscoveryState()) {
    on<StartDiscovery>(_onStart);
    on<StopDiscovery>(_onStop);
    on<NeighborsUpdated>(_onNeighborsUpdated);
    on<RefreshNeighbors>(_onRefresh);
  }

  Future<void> _onStart(
    StartDiscovery event,
    Emitter<DiscoveryState> emit,
  ) async {
    try {
      emit(state.copyWith(isDiscovering: true, error: null));

      // Discovery is managed by MeshBloc → MeshRepository → startMeshNode.
      // DiscoveryBloc only subscribes to the neighbor stream.
      _neighborsSubscription?.cancel();
      _neighborsSubscription = _wifiP2pSource.discoveredNodes.listen(
        (neighbors) => add(NeighborsUpdated(neighbors)),
      );
    } catch (e) {
      emit(state.copyWith(
        isDiscovering: false,
        error: e.toString(),
      ));
    }
  }

  Future<void> _onStop(
    StopDiscovery event,
    Emitter<DiscoveryState> emit,
  ) async {
    await _neighborsSubscription?.cancel();
    _neighborsSubscription = null;

    // Discovery lifecycle is controlled by MeshBloc (startMeshNode/stopMeshNode).
    // We only toggle the local UI state here.
    emit(state.copyWith(isDiscovering: false));
  }

  Future<void> _onNeighborsUpdated(
    NeighborsUpdated event,
    Emitter<DiscoveryState> emit,
  ) async {
    final neighbors = event.neighbors
        .whereType<NodeInfo>()
        .where((n) => !n.isStale)
        .toList();

    emit(state.copyWith(
      neighbors: neighbors,
      lastRefresh: DateTime.now(),
    ));
  }

  Future<void> _onRefresh(
    RefreshNeighbors event,
    Emitter<DiscoveryState> emit,
  ) async {
    // Native auto-refreshes discovery every 15-20s.
    // Manual refresh is a no-op; the stream will update automatically.
  }

  @override
  Future<void> close() {
    _neighborsSubscription?.cancel();
    return super.close();
  }
}
