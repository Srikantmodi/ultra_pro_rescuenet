import 'package:equatable/equatable.dart';

/// Transmission BLoC state.
class TransmissionState extends Equatable {
  final bool isSending;
  final List<TransmissionRecord> history;
  final String? currentPacketId;
  final String? error;

  const TransmissionState({
    this.isSending = false,
    this.history = const [],
    this.currentPacketId,
    this.error,
  });

  TransmissionState copyWith({
    bool? isSending,
    List<TransmissionRecord>? history,
    String? currentPacketId,
    String? error,
  }) {
    return TransmissionState(
      isSending: isSending ?? this.isSending,
      history: history ?? this.history,
      currentPacketId: currentPacketId,
      error: error,
    );
  }

  int get successCount => history.where((r) => r.success).length;
  int get failureCount => history.where((r) => !r.success).length;

  @override
  List<Object?> get props => [isSending, history, currentPacketId, error];
}

/// Record of a transmission attempt.
class TransmissionRecord extends Equatable {
  final String packetId;
  final String? targetNodeId;
  final bool success;
  final DateTime timestamp;
  final String? error;

  const TransmissionRecord({
    required this.packetId,
    this.targetNodeId,
    required this.success,
    required this.timestamp,
    this.error,
  });

  @override
  List<Object?> get props => [packetId, success, timestamp];
}
