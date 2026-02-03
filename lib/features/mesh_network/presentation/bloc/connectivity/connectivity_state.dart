import 'package:equatable/equatable.dart';

/// Connectivity BLoC state.
class ConnectivityState extends Equatable {
  final bool isConnected;
  final String connectionType;
  final bool isChecking;
  final DateTime? lastChecked;

  const ConnectivityState({
    this.isConnected = false,
    this.connectionType = 'unknown',
    this.isChecking = false,
    this.lastChecked,
  });

  ConnectivityState copyWith({
    bool? isConnected,
    String? connectionType,
    bool? isChecking,
    DateTime? lastChecked,
  }) {
    return ConnectivityState(
      isConnected: isConnected ?? this.isConnected,
      connectionType: connectionType ?? this.connectionType,
      isChecking: isChecking ?? this.isChecking,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }

  @override
  List<Object?> get props => [isConnected, connectionType, isChecking, lastChecked];
}
