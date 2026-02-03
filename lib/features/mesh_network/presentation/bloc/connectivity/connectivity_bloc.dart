import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/services/internet_probe.dart';
import 'connectivity_event.dart';
import 'connectivity_state.dart';

/// BLoC for managing connectivity state.
class ConnectivityBloc extends Bloc<ConnectivityEvent, ConnectivityState> {
  final InternetProbe _probe;
  Timer? _monitorTimer;

  ConnectivityBloc({InternetProbe? probe})
      : _probe = probe ?? InternetProbe(),
        super(const ConnectivityState()) {
    on<StartConnectivityMonitoring>(_onStart);
    on<StopConnectivityMonitoring>(_onStop);
    on<ConnectivityChanged>(_onChanged);
    on<CheckConnectivity>(_onCheck);
  }

  Future<void> _onStart(
    StartConnectivityMonitoring event,
    Emitter<ConnectivityState> emit,
  ) async {
    // Initial check
    add(CheckConnectivity());

    // Start periodic monitoring
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => add(CheckConnectivity()),
    );
  }

  Future<void> _onStop(
    StopConnectivityMonitoring event,
    Emitter<ConnectivityState> emit,
  ) async {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  Future<void> _onChanged(
    ConnectivityChanged event,
    Emitter<ConnectivityState> emit,
  ) async {
    emit(state.copyWith(
      isConnected: event.isConnected,
      connectionType: event.connectionType,
      lastChecked: DateTime.now(),
    ));
  }

  Future<void> _onCheck(
    CheckConnectivity event,
    Emitter<ConnectivityState> emit,
  ) async {
    emit(state.copyWith(isChecking: true));

    final hasInternet = await _probe.checkConnectivity();

    emit(state.copyWith(
      isConnected: hasInternet,
      connectionType: hasInternet ? 'internet' : 'offline',
      isChecking: false,
      lastChecked: DateTime.now(),
    ));
  }

  @override
  Future<void> close() {
    _monitorTimer?.cancel();
    return super.close();
  }
}
