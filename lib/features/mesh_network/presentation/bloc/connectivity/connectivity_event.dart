import 'package:equatable/equatable.dart';

/// Connectivity BLoC events.
abstract class ConnectivityEvent extends Equatable {
  const ConnectivityEvent();

  @override
  List<Object?> get props => [];
}

/// Start monitoring connectivity.
class StartConnectivityMonitoring extends ConnectivityEvent {}

/// Stop monitoring connectivity.
class StopConnectivityMonitoring extends ConnectivityEvent {}

/// Connectivity changed.
class ConnectivityChanged extends ConnectivityEvent {
  final bool isConnected;
  final String connectionType;

  const ConnectivityChanged({
    required this.isConnected,
    required this.connectionType,
  });

  @override
  List<Object?> get props => [isConnected, connectionType];
}

/// Check connectivity now.
class CheckConnectivity extends ConnectivityEvent {}
